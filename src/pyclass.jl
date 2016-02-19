# Define Python classes out of Julia types

using MacroTools: @capture


######################################################################
# Dispatching methods. They convert the PyObject arguments into Julia objects,
# and passes them to the Julia function `fun`

# helper for `def_py_methods`. This will call
#    fun(self_::T, args...; kwargs...)
# where `args` and `kwargs` are parsed from `args_`
function dispatch_to{T}(jl_type::Type{T}, fun::Function,
                        self_::PyPtr, args_::PyPtr, kw_::PyPtr)
    # adapted from jl_Function_call
    ret_ = convert(PyPtr, C_NULL)
    args = PyObject(args_)
    try
        self = unsafe_pyjlwrap_to_objref(self_)::T
        if kw_ == C_NULL
            ret = PyObject(fun(self, convert(PyAny, args)...))
        else
            kw = PyDict{Symbol,PyAny}(PyObject(kw_))
            kwargs = [ (k,v) for (k,v) in kw ]
            ret = PyObject(fun(self, convert(PyAny, args)...; kwargs...))
        end
        ret_ = ret.o
        ret.o = convert(PyPtr, C_NULL) # don't decref
    catch e
        pyraise(e)
    finally
        args.o = convert(PyPtr, C_NULL) # don't decref
    end
    return ret_::PyPtr
end


# Dispatching function for getters (what happens when `obj.some_field` is
# called in Python). `fun` should be a Julia function that accepts (::T), and
# returns some value (it doesn't have to be an actual field of T)
function dispatch_get{T}(jl_type::Type{T}, fun::Function, self_::PyPtr)
    try
        obj = unsafe_pyjlwrap_to_objref(self_)::T
        ret = fun(obj)
        return pyincref(PyObject(ret)).o
    catch e
        pyraise(e)
    end
    return convert(PyPtr, C_NULL)
end

# The setter should accept a `new_value` argument. Return value is ignored.
function dispatch_set{T}(jl_type::Type{T}, fun::Function, self_::PyPtr,
                         value_::PyPtr)
    value = PyObject(value_)
    try
        obj = unsafe_pyjlwrap_to_objref(self_)::T
        fun(obj, convert(PyAny, value))
        return 0 # success
    catch e
        pyraise(e)
    finally
        value.o = convert(PyPtr, C_NULL) # don't decref
    end
    return -1 # failure
end



# This vector will grow on each new type (re-)definition, and never free memory.
# FIXME. I'm not sure how to detect if the corresponding Python types have
# been GC'ed.
const all_method_defs = Any[] 


"""    make_method_defs(jl_type, methods)

Create the PyMethodDef methods, stores them permanently (to prevent GC'ing),
and returns them in a Vector{PyMethodDef} """
function make_method_defs(jl_type, methods)
    method_defs = PyMethodDef[]
    for (py_name, jl_fun) in methods
        # `disp_fun` is really like the closure:
        #    (self_, args_) -> dispatch_to(jl_type, jl_fun, self_, args_)
        # but `cfunction` complains if we use that.
        disp_fun =
            @eval function $(gensym(string(jl_fun)))(self_::PyPtr, args_::PyPtr,
                                                     kw_::PyPtr)
                dispatch_to($jl_type, $jl_fun, self_, args_, kw_)
            end
        push!(method_defs, PyMethodDef(py_name, disp_fun, METH_KEYWORDS))
    end
    push!(method_defs, PyMethodDef()) # sentinel

    # We have to make sure that the PyMethodDef vector isn't GC'ed by Julia, so
    # we push them onto a global stack.
    push!(all_method_defs, method_defs)
    return method_defs
end

# Similar to make_method_defs
function make_getset_defs(jl_type, getsets::Vector)
    # getters and setters have a `closure` parameter (here `_`), but it
    # was ignored in all the examples I've seen.
    make_getter(getter_fun) = 
        @eval function $(gensym())(self_::PyPtr, _::Ptr{Void})
            dispatch_get($jl_type, $getter_fun, self_)
        end
    make_setter(setter_fun) = 
        @eval function $(gensym())(self_::PyPtr, value_::PyPtr, _::Ptr{Void})
            dispatch_set($jl_type, $setter_fun, self_, value_)
        end

    getset_defs = PyGetSetDef[]
    for getset in getsets
        # We also support getset tuples of the form
        #    ("x", some_function, nothing)
        @assert 2<=length(getset)<=3 "`getset` argument must be 2 or 3-tuple"
        if (length(getset) == 3 && getset[3] !== nothing)
            (member_name, getter_fun, setter_fun) = getset
            push!(getset_defs, PyGetSetDef(member_name, make_getter(getter_fun),
                                           make_setter(setter_fun)))
        else
            (member_name, getter_fun) = getset
            push!(getset_defs, PyGetSetDef(member_name,
                                           make_getter(getter_fun)))
        end
    end
    push!(getset_defs, PyGetSetDef()) # sentinel

    push!(all_method_defs, getset_defs)    # Make sure it's not GC'ed
    return getset_defs
end

function def_py_methods{T}(jl_type::Type{T}, methods...;
                           base_class=pybuiltin(:object),
                           getsets=[])
    if base_class === nothing base_class = pybuiltin(:object) end # temp DELETEME
    method_defs = make_method_defs(jl_type, methods)
    getset_defs = make_getset_defs(jl_type, getsets)

    # Create the Python type
    typename = jl_type.name.name::Symbol
    py_typ = pyjlwrap_type("PyCall.$typename", t -> begin 
        t.tp_getattro = @pyglobal(:PyObject_GenericGetAttr)
        t.tp_methods = pointer(method_defs)
        t.tp_getset = pointer(getset_defs)
        # Unfortunately, this supports only single-inheritance. See
        # https://docs.python.org/2/c-api/typeobj.html#c.PyTypeObject.tp_base
        # to add multiple-inheritance support
        t.tp_base = base_class.o # Needs pyincref?
    end)

    @eval function PyObject(obj::$T)
        pyjlwrap_new($py_typ, obj)
    end

    py_typ
end
 

######################################################################
# @pydef macro


function parse_pydef(expr)
    # We're not getting that much value out of @capture, we could take it
    # out and get rid of the MacroTools dependency
    if !@capture(expr, begin type type_name_ <: base_class_
                    lines__
                end end)
        @assert(@capture(expr, type type_name_
                    lines__
            end), "Malformed @pydef expression")
        base_class = nothing
    end
    function_defs = Any[]
    methods = Tuple[]
    getter_dict = Dict()
    setter_dict = Dict()
    method_syms = Dict()
    if isa(lines[1], Expr) && lines[1].head == :block 
        # unfortunately, @capture fails to parse the `type` correctly
        lines = lines[1].args
    end
    for line in lines
        if !isa(line, LineNumberNode) && line.head != :line # need to skip those
            @assert line.head == :(=) "Malformed line: $line"
            lhs, rhs = line.args
            @assert @capture(lhs,py_f_(args__)) "Malformed left-hand-side: $lhs"
            if isa(py_f, Symbol)
                # Method definition
                # We save the gensym to support multiple dispatch
                #    readlines(io) = ...
                #    readlines(io, nlines) = ...
                # otherwise the first and second `readlines` get different
                # gensyms, and one of the two gets ignored
                jl_fun_name = get!(method_syms, py_f, gensym(py_f))
                push!(function_defs, :(function $jl_fun_name($(args...))
                    $rhs
                end))
                push!(methods, (string(py_f), jl_fun_name))
            elseif @capture(py_f, attribute_.access_)
                # Accessor (.get/.set) definition
                if access == :get
                    dict = getter_dict
                elseif access == :set!
                    dict = setter_dict
                else
                    error("Bad accessor type $access; must be either get or set!")
                end
                jl_fun_name = gensym(symbol(attribute,:_,access))
                push!(function_defs, :(function $jl_fun_name($(args...))
                    $rhs
                end))
                dict[string(attribute)] = jl_fun_name
            else
                error("Malformed line: $line")
            end
        end
    end
    @assert(isempty(setdiff(keys(setter_dict), keys(getter_dict))),
            "All .set attributes must have a .get")
    type_name, base_class, methods, getter_dict, setter_dict, function_defs
end


macro pydef(type_expr)
    type_name, base_class, methods_, getter_dict, setter_dict, function_defs =
        parse_pydef(type_expr)
    methods = [:($py_name, $(esc(jl_fun::Symbol)))
               for (py_name, jl_fun) in methods_]
    getsets = [:($attribute,
                 $(esc(getter)),
                 $(esc(get(setter_dict, attribute, nothing))))
               for (attribute, getter) in getter_dict]
    :(begin
        $(map(esc, function_defs)...)
        def_py_methods($(esc(type_name)), $(methods...);
                       base_class=$(esc(base_class)),
                       getsets=[$(getsets...)])
    end)
end
