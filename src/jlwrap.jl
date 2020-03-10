################################################################
# Wrap a Python type around a Julia Any object



##########################################################
# permanent cacheing

const GLOBAL_CACHE = Base.IdDict()

function cached(x)
    get!(GLOBAL_CACHE, x, x) :: typeof(x)
end

cached_string_pointer(x::String) = unsafe_convert(Ptr{UInt8}, cached(x))
cached_string_pointer(x::AbstractString) = cached_string_pointer(String(x))
cached_string_pointer(x::Ptr) = convert(Ptr{UInt8}, x)

cached_string_pointer_or_NULL(x::AbstractString) =
    isempty(x) ? Ptr{UInt8}(C_NULL) : cached_string_pointer(x)
cached_string_pointer_or_NULL(x::Ptr) = cached_string_pointer(x)

cached_ref(x) = cached(Ref(x))
cached_ref(x::Ref) = cached(x)

cached_ref_pointer(x) = cached_ref_pointer(Ref(x))
cached_ref_pointer(x::Ref) = unsafe_convert(Ptr{eltype(x)}, cached(x))





##########################################################
# convenience functions for making C structures

CPyMethodDef(; name=C_NULL, meth=C_NULL, flags=0, doc=C_NULL) =
    CPyMethodDef(cached_string_pointer(name), convert(Ptr{Cvoid}, meth), convert(Cint, flags), cached_string_pointer_or_NULL(doc))

CPyGetSetDef(; name=C_NULL, get=C_NULL, set=C_NULL, doc=C_NULL, closure=C_NULL) =
    CPyGetSetDef(cached_string_pointer(name), convert(Ptr{Cvoid}, get), convert(Ptr{Cvoid}, set), cached_string_pointer_or_NULL(doc), convert(Ptr{Cvoid}, closure))

CPyMemberDef(; name=C_NULL, typ=0, offset=0, flags=0, doc=C_NULL) =
    CPyMemberDef(cached_string_pointer(name), convert(Cint, typ), convert(Int, offset), convert(Cint, flags), cached_string_pointer_or_NULL(doc))

@eval CPyNumberMethods(; $([Expr(:kw, n, C_NULL) for n in fieldnames(CPyNumberMethods)]...)) = CPyNumberMethods($([:(convert(Ptr{Cvoid}, $n)) for n in fieldnames(CPyNumberMethods)]...))

@eval CPySequenceMethods(; $([Expr(:kw, n, C_NULL) for n in fieldnames(CPySequenceMethods)]...)) = CPySequenceMethods($([:(convert(Ptr{Cvoid}, $n)) for n in fieldnames(CPySequenceMethods)]...))

@eval CPyMappingMethods(; $([Expr(:kw, n, C_NULL) for n in fieldnames(CPyMappingMethods)]...)) = CPyMappingMethods($([:(convert(Ptr{Cvoid}, $n)) for n in fieldnames(CPyMappingMethods)]...))

@eval function CPyTypeObject(; initialize=true, $([Expr(:kw, n, t<:Ptr ? C_NULL : 0) for (n,t) in zip(fieldnames(CPyTypeObject), fieldtypes(CPyTypeObject))]...))
    # convert inputs
    if tp_name isa AbstractString
        tp_name = cached_string_pointer(tp_name)
    end
    if tp_as_number isa CPyNumberMethods
        tp_as_number = cached_ref_pointer(tp_as_number)
    end
    if tp_as_sequence isa CPySequenceMethods
        tp_as_sequence = cached_ref_pointer(tp_as_sequence)
    end
    if tp_as_mapping isa CPyMappingMethods
        tp_as_mapping = cached_ref_pointer(tp_as_mapping)
    end
    if tp_members isa AbstractVector{CPyMemberDef}
        tp_members = pointer(cached([tp_members; CPyMemberDef_NULL]))
    end
    if tp_methods isa AbstractVector{CPyMethodDef}
        tp_methods = pointer(cached([tp_methods; CPyMethodDef_NULL]))
    end
    if tp_getset isa AbstractVector{CPyGetSetDef}
        tp_getset = pointer(cached([tp_getset; CPyGetSetDef_NULL]))
    end
    if tp_base isa Ref{CPyTypeObject}
        tp_base = cached_ref_pointer(tp_base)
    end
    # make the type
    CPyTypeObject($([:(convert($t, $n)) for (n,t) in zip(fieldnames(CPyTypeObject), fieldtypes(CPyTypeObject))]...))
end

macro cpymethod(name)
    :(@cfunction($name, PyPtr, (PyPtr, PyPtr)))
end

macro cpygetfunc(name)
    :(@cfunction($name, PyPtr, (PyPtr, Ptr{Cvoid})))
end










##########################################################
# The jlwrap object

struct CPyJlWrapObject
    # PyObject_HEAD (for non-Py_TRACE_REFS build):
    ob_refcnt::Int
    ob_type::PyPtr # actually Ptr{PyTypeObject}

    ob_weakrefs::PyPtr
    jl_value::Any
end

field_pointer(ptr::Ptr{T}, i) where {T} =
    convert(Ptr{fieldtype(T, i)}, convert(Ptr{Cvoid}, ptr) + fieldoffset(T, i))

unsafe_store_field!(ptr::Ptr, val, i) =
    unsafe_store!(field_pointer(ptr, i), val)

unsafe_load_field(ptr::Ptr, i) =
    unsafe_load(field_pointer(ptr, i))

unsafe_pytype(o::PyPtr) =
    convert(Ptr{CPyTypeObject}, unsafe_load_field(o, 2))

unsafe_pyjlwrap_ptr(o::Union{PyPtr, PyObject}) =
    convert(Ptr{CPyJlWrapObject}, PyPtr(o))

unsafe_pyjlwrap_value_ptr(o::Union{PyPtr, PyObject}) =
    Ptr{Ptr{Cvoid}}(field_pointer(unsafe_pyjlwrap_ptr(o), 4))

unsafe_pyjlwrap_load_value(o::Union{PyPtr, PyObject}) =
    GC.@preserve o unsafe_pointer_to_objref(unsafe_load(unsafe_pyjlwrap_value_ptr(o)))

unsafe_pyjlwrap_store_value!(o::Union{PyPtr, PyObject}, p::Ptr) =
    unsafe_store!(unsafe_pyjlwrap_value_ptr(o), p)

function CPyJlWrap_New(T::Ref{CPyTypeObject}, value) :: PyPtr
    # make the new object
    o = CPyObject_New(T)
    o == C_NULL && (return C_NULL)
    # make a pointer to the value
    if isimmutable(value)
        # It is undefined to call `pointer_from_objref` on immutable objects.
        # The compiler is free to return basically anything since the boxing is not
        # significant at all.
        # Below is a well defined way to get a pointer (`ptr`) and an object that defines
        # the lifetime of the pointer `ref`.
        ref = Ref{Any}(value)
        pycall_gc[o] = ref
        ptr = unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(ref)))
    else
        pycall_gc[o] = value
        ptr = pointer_from_objref(value)
    end
    # store the relevant pointers
    unsafe_store_field!(unsafe_pyjlwrap_ptr(o), C_NULL, 3)
    unsafe_pyjlwrap_store_value!(o, ptr)
    return o
end

is_pyjlwrap(o::Union{PyObject,PyPtr}) =
    CPyJlWrap_Type[].tp_new != C_NULL &&
    CPyObject_IsInstance(o, CPyJlWrap_Type) == 1








##########################################################
# members and methods


# destructor for jlwrap instance, assuming it was created with pyjlwrap_new
function _pyjlwrap_dealloc(o::PyPtr)
    p = unsafe_pyjlwrap_ptr(o)
    if unsafe_load_field(p, 3) != C_NULL
        PyObject_ClearWeakRefs(o)
    end
    delete!(pycall_gc, o)
    return nothing
end

pyerrorval(::Type{PyPtr}) = PyPtr_NULL
pyerrorval(::Type{T}) where {T<:Integer} = zero(T) - one(T)

macro pyjlwrapfunc(ex)
    def = MacroTools.splitdef(ex)
    def[:name] = Symbol(:_pyjlwrap_, def[:name])
    selfarg = def[:args][1]
    (self, selftype, selfslurp, selfdefault) = MacroTools.splitarg(selfarg)
    _self = Symbol(:_, self)
    err = gensym()
    def[:args][1] = :($_self :: PyPtr)
    def[:body] = quote
        $self :: $selftype = unsafe_pyjlwrap_load_value($_self)
        try
            $(def[:body])
        catch $err
            @pyraise $err
        end
        $(pyerrorval(eval(def[:rtype])))
    end
    r = MacroTools.combinedef(def)
end

@pyjlwrapfunc function repr(o)::PyPtr
    return CPyUnicode_From(repr(o))
end

@pyjlwrapfunc function str(o)::PyPtr
    return CPyUnicode_From(string(o))
end

@pyjlwrapfunc function hash(o)::UInt
    h = hash(o)
    # Python hashes are not permitted to return -1!!
    return h == reinterpret(UInt, -1) ? pysalt::UInt : h::UInt
end

# 32-bit hash on 64-bit machines, needed for Python < 3.2 with Windows
const pysalt32 = 0xb592cd9b # hash("PyCall") % UInt32
@pyjlwrapfunc function hash32(o)::UInt32
    h = ccall(:int64to32hash, UInt32, (UInt64,), hash(o))
    # Python hashes are not permitted to return -1!!
    return h == reinterpret(UInt32, Int32(-1)) ? pysalt32 : h::UInt32
end

function _pyjlwrap_call(f_::PyPtr, args_::PyPtr, kw_::PyPtr)::PyPtr
    f = unsafe_pyjlwrap_load_value(f_)
    args = PyObject(args_) # don't need pyincref because of finally clause below
    try
        jlargs = julia_args(f, args)

        # we need to use invokelatest to get execution in newest world
        if kw_ == C_NULL
            ret = Base.invokelatest(f, jlargs...)
        else
            kw = PyDict{Symbol,PyObject}(pyincref(kw_))
            kwargs = [ (k,julia_kwarg(f,k,v)) for (k,v) in kw ]

            # 0.6 `invokelatest` doesn't support kwargs, instead
            # use a closure over kwargs. see:
            #   https://github.com/JuliaLang/julia/pull/22646
            f_kw_closure() = f(jlargs...; kwargs...)
            ret = Core._apply_latest(f_kw_closure)
        end

        @pyreturn ret
    catch e
        @pyraise e
    finally
        setfield!(args, :o, PyPtr_NULL) # don't decref
    end
    return PyPtr_NULL
end

@pyjlwrapfunc function length(o)::Cssize_t
    return length(o)
end

@pyjlwrapfunc function istrue(o)::Cint
    return _pyistrue(x)::Bool
end

@pyjlwrapfunc function istrue_always(o)::Cint
    return return true
end

_pyistrue(x) =
    try
        !iszero(x)
    catch
        try
            !isempty(x)
        catch
            true
        end
    end
_pyistrue(::Union{Ref,Function}) = true
_pyistrue(::Union{Nothing,Missing}) = false
_pyistrue(x::Bool) = x
_pyistrue(x::Number) = !iszero(x)
_pyistrue(x::Union{AbstractArray,AbstractDict,Tuple,Pair,NamedTuple,AbstractSet,AbstractString}) = !isempty(x)
_pyistrue(x::Symbol) = x != Symbol()
_pyistrue(x::Ptr) = x != C_NULL

@pyjlwrapfunc function istrue_number(o)::Cint
    return !iszero(o)
end

@pyjlwrapfunc function istrue_collection(o)::Cint
    return !isempty(o)
end


@pyjlwrapfunc function int(o)::PyPtr
    return CPyLong_From(o)
end

@pyjlwrapfunc function float(o)::PyPtr
    return CPyFloat_From(o)
end

@pyjlwrapfunc function complex(o, ::PyPtr)::PyPtr
    return CPyComplex_From(o)
end

function _pyjlwrap_richcompare(_a::PyPtr, _b::PyPtr, op::Cint)::PyPtr
    (is_pyjlwrap(_a) && is_pyjlwrap(_b)) || (return CPy_NotImplemented_NewRef())
    a = unsafe_pyjlwrap_load_value(_a)
    b = unsafe_pyjlwrap_load_value(_b)
    try
        r =
            op == Py_LT ? a < b :
            op == Py_LE ? a ≤ b :
            op == Py_EQ ? a == b :
            op == Py_NE ? a != b :
            op == Py_GT ? a > b :
            op == Py_GE ? a ≥ b :
            error("invalid op")
        return CPyBool_From(r)
    catch e
        e isa MethodError && (return CPy_NotImplemented_NewRef())
        @pyraise e
    end
    return C_NULL
end

@pyjlwrapfunc function getitem(o, i::PyPtr)::PyPtr
    @pyreturn _pygetitem(o, pyincref(i))
end

@pyjlwrapfunc function getitem_oneup(o, i::Cssize_t)::PyPtr
    @pyreturn o[i+1]
end

@pyjlwrapfunc function getitem_oneup(o, _i::PyPtr)::PyPtr
    i = convert(Union{Int,Tuple{Vararg{Int}}}, pyincref(_i)) .+ 1
    @pyreturn o[i...]
end

@pyjlwrapfunc function setitem_oneup(o, _i::PyPtr, _x::PyPtr)::Cint
    i = convert(Union{Int, Tuple{Vararg{Int}}}, pyincref(_i)) .+ 1
    o[i...] = _pyvalueatindex(o, i, _x)
    return 0
end

@pyjlwrapfunc function getitem_namedtuple(o, _i::PyPtr)::PyPtr
    i = convert(Union{Int,Symbol}, pyincref(_i))
    if i isa Int
        @pyreturn o[i+1]
    else
        @pyreturn o[i]
    end
end

_pygetitem(o, i::PyObject) = _pygetitem(o, _pyindex(o, i))
_pygetitem(o, i) = getindex(o, i)
_pygetitem(o, i::Tuple) = applicable(getindex, o, i...) ? getindex(o, i...) : getindex(o, i)

function _pyindex(o, i)
    T = applicable(keytype, o) ? keytype(o) : Any
    T = T==Any ? PyAny : Union{T,PyAny}
    convert(T, i)
end
_pyindex(o::NamedTuple, i::PyObject) = convert(Union{Symbol,Int}, i)

@pyjlwrapfunc function setitem(o, i::PyPtr, x::PyPtr)::Cint
    _pysetitem(o, pyincref(i), pyincref(x))
    return 0
end

function _pysetitem(o, i, x)
    i = _pyindex(o, i)
    x = _pyvalueatindex(o, i, x)
    setindex!(o, x, i)
end

function _pyvalueatindex(o, i, x)
    T = applicable(eltype, o) ? eltype(o) : Any
    T = T==Any ? PyAny : Union{T,PyAny}
    convert(T, x)
end

function _pyjlwrap_getattr(_self::PyPtr, _attr::PyPtr)::PyPtr
    self = unsafe_pyjlwrap_load_value(_self)
    attr = CPyUnicode_As(String, _attr)
    attr===nothing && (return PyPtr_NULL)
    try
        # do the generic lookup in __dict__ first
        r = CPyObject_GenericGetAttr(_self, _attr)
        pyerr_occurred(CPyExc_AttributeError[]) || (return r)
        # now do special attributes
        if attr == "__doc__"
            return CPyUnicode_From(string(Docs.doc(self)))
        elseif startswith(attr, "__julia_field_")
            a = Symbol(attr[15:end])
            if hasfield(typeof(self), a)
                pyerr_clear()
                @pyreturn getfield(self, a)
            end
        elseif startswith(attr, "__julia_property_")
            a = Symbol(attr[18:end])
            if hasproperty(self, a)
                pyerr_clear()
                @pyreturn getproperty(self, a)
            end
        else
            a = Symbol(attr)
            if hasproperty(self, a)
                pyerr_clear()
                @pyreturn getproperty(self, a)
            end
        end
        # on failure, propagate the attribute error
        return r
    catch e
        @pyraise e
    end
    return PyPtr_NULL
end

function _pyjlwrap_setattr(self_::PyPtr, attr__::PyPtr, value_::PyPtr)::Cint
    value_ == C_NULL && return pyjlwrap_delattr(self_, attr__)
    attr_ = PyObject(attr__)
    value = pyincref(value_)
    try
        self = unsafe_pyjlwrap_load_value(self_)
        attr = convert(String, attr_)
        @show self attr
        if startswith(attr, "__")
            if startswith(attr, "__julia_field_")
                _pysetfield(self, Symbol(attr[15:end]), value)
            elseif startswith(attr, "__julia_property_")
                _pysetproperty(self, Symbol(attr[18:end]), value)
            else
                return PyObject_GenericSetAttr(self_, attr__, value_)
            end
        else
            _pysetproperty(self, Symbol(attr), value)
        end
        return 0
    catch e
        @pyraise e
    finally
        setfield!(attr_, :o, PyPtr_NULL)
    end
    return -1
end

function _pyjlwrap_dir(_o::PyPtr, ::PyPtr)::PyPtr
    # the default implementation
    d = PyObject(CPyObject_GetAttrString(CPyBaseObject_Type[], "__dir__"))
    ispynull(d) && return C_NULL
    r = PyObject(CPyObject_CallFunction(d, _o))
    ispynull(r) && return C_NULL
    # add fields and properties of the julia object
    o = unsafe_pyjlwrap_load_value(_o)
    try
        custom = String[]
        for n in fieldnames(typeof(o))
            push!(custom, "__julia_field_$n")
        end
        for n in propertynames(o)
            push!(custom, "$n")
            push!(custom, "__julia_property_$n")
        end
        for n in custom
            s = PyObject(CPyUnicode_From(n))
            ispynull(s) && return C_NULL
            z = CPyList_Append(r, s)
            z == -1 && return C_NULL
        end
        return pystealref!(r)
    catch e
        @pyraise e
    end
    return C_NULL
end

function _pysetproperty(o, f, x)
    x = _pyvalueatproperty(o, f, x)
    setproperty!(o, f, x)
end

function _pyvalueatproperty(o, f, x)
    convert(PyAny, x)
end

function _pysetfield(o, f, x)
    x = _pyvalueatfield(o, f, x)
    setfield!(o, f, x)
end

function _pyvalueatfield(o, f, x)
    T = fieldtype(typeof(o), f)
    T = T==Any ? PyAny : T
    convert(T, x)
end

# tp_iternext object of a jlwrap_iterator object, similar to PyIter_Next
@pyjlwrapfunc function iternext(self)::PyPtr
    iter, iter_result_ref = self
    iter_result = iter_result_ref[]
    if iter_result !== nothing
        item, state = iter_result
        iter_result_ref[] = iterate(iter, state)
        @pyreturn item
    end
end

# the tp_iter slot of jlwrap object: like PyObject_GetIter, it
# returns a reference to a new jlwrap_iterator object
@pyjlwrapfunc function getiter(self)::PyPtr
    return CPyJlWrapIterator_From(self)
end

@pyjlwrapfunc function getiter_keys(self)::PyPtr
    return CPyJlWrapIterator_From(keys(self))
end

@pyjlwrapfunc function getiter_lines(self)::PyPtr
    return CPyJlWrapIterator_From(eachline(self))
end

for (a,b) in [(:negative,:-), (:positive, :+), (:absolute, :abs), (:invert, :~)]
    @eval @pyjlwrapfunc function $a(self)::PyPtr
        return CPyJlWrap_From($b(self))
    end
end

for (a,b) in [(:add, :+), (:subtract, :-), (:multiply, :*), (:remainder, :mod), (:lshift, :(<<)), (:rshift, :(>>)), (:and, :&), (:xor, :⊻), (:or, :|), (:floordivide, :fld), (:truedivide, :/)]
    @eval function $(Symbol(:_pyjlwrap_, a))(a_::PyPtr, b_::PyPtr)::PyPtr
        (is_pyjlwrap(a_) && is_pyjlwrap(b_)) ||
            (return CPy_NotImplemented_NewRef())
        try
            a = unsafe_pyjlwrap_load_value(a_)
            b = unsafe_pyjlwrap_load_value(b_)
            return CPyJlWrap_From($b(a, b))
        catch e
            @pyraise e
        end
        return C_NULL
    end
end

function _pyjlwrap_power(_a::PyPtr, _b::PyPtr, _c::PyPtr)::PyPtr
    if _c == CPy_None[]
        (is_pyjlwrap(_a) && is_pyjlwrap(_b)) ||
            (return CPy_NotImplemented_NewRef())
        a = unsafe_pyjlwrap_load_value(_a)
        b = unsafe_pyjlwrap_load_value(_b)
        try
            return CPyJlWrap_From(a^b)
        catch e
            @pyraise e
        end
        return C_NULL
    else
        return CPy_NotImplemented_NewRef()
    end
end

@pyjlwrapfunc function get_real(self, ::Ptr{Cvoid})::PyPtr
    return CPyJlWrapReal_From(real(self))
end

@pyjlwrapfunc function get_imag(self, ::Ptr{Cvoid})::PyPtr
    return CPyJlWrapReal_From(imag(self))
end

@pyjlwrapfunc function conjugate(self, ::PyPtr)::PyPtr
    return CPyJlWrapNumber_From(conj(self))
end

@pyjlwrapfunc function trunc(self, ::PyPtr)::PyPtr
    return CPyJlWrapIntegral_From(trunc(Integer, self))
end

@pyjlwrapfunc function round(self, ::PyPtr)::PyPtr
    return CPyJlWrapIntegral_From(round(Integer, self))
end

@pyjlwrapfunc function floor(self, ::PyPtr)::PyPtr
    return CPyJlWrapIntegral_From(floor(Integer, self))
end

@pyjlwrapfunc function ceil(self, ::PyPtr)::PyPtr
    return CPyJlWrapIntegral_From(ceil(Integer, self))
end

@pyjlwrapfunc function get_numerator(self, ::Ptr{Cvoid})::PyPtr
    return CPyJlWrapIntegral_From(numerator(self))
end

@pyjlwrapfunc function get_denominator(self, ::Ptr{Cvoid})::PyPtr
    return CPyJlWrapIntegral_From(denominator(self))
end

@pyjlwrapfunc function io_close(self, ::PyPtr)::PyPtr
    close(self)
    return CPy_None_NewRef()
end

@pyjlwrapfunc function io_fileno(self, ::PyPtr)::PyPtr
    return CPyLong_From(fd(self))
end

@pyjlwrapfunc function io_get_closed(self, ::Ptr{Cvoid})::PyPtr
    return CPyBool_From(!isopen(self))
end

@pyjlwrapfunc function io_flush(self, ::PyPtr)::PyPtr
    flush(self)
    return CPy_None_NewRef()
end

@pyjlwrapfunc function io_isatty(self, ::PyPtr)::PyPtr
    return CPyBool_From(self isa Base.TTY)
end

@pyjlwrapfunc function io_readable(self, ::PyPtr)::PyPtr
    return CPyBool_From(isreadable(self))
end

@pyjlwrapfunc function io_writable(self, ::PyPtr)::PyPtr
    return CPyBool_From(iswritable(self))
end

@pyjlwrapfunc function io_truncate(self, args::PyPtr)::PyPtr
    r = @CPyArg_ParseTuple(args, sz::Int=nothing)
    r===nothing && return C_NULL
    (sz,) = r
    sz = sz===nothing ? position(self) : sz
    truncate(self, sz)
    return CPyLong_From(sz)
end

@pyjlwrapfunc function io_seek(self, args::PyPtr)::PyPtr
    r = @CPyArg_ParseTuple(args, off::Int, wh::Int=0)
    r===nothing && return C_NULL
    (off, wh) = r
    if wh==0
        seek(self, off)
    elseif wh==1
        seek(self, position(self) + off)
    elseif wh==2
        seekend(self)
        len = position(self)
        seek(self, len + off)
    else
        error("invalid whence")
    end
    return CPyLong_From(position(self))
end

@pyjlwrapfunc function io_seekable(self, ::PyPtr)::PyPtr
    # can we improve this?
    return CPy_True_NewRef()
end

@pyjlwrapfunc function io_tell(self, ::PyPtr)::PyPtr
    return CPyLong_From(position(self))
end

@pyjlwrapfunc function bufferedio_read(self, args::PyPtr)::PyPtr
    r = @CPyArg_ParseTuple(args, n::Int=-1)
    r===nothing && return C_NULL
    (n,) = r
    v = n<0 ? read(self) : read(self, n)
    return CPyBytes_FromStringAndSize(v, length(v))
end

@pyjlwrapfunc function bufferedio_readinto(self, b::PyPtr)::PyPtr
    buf = PyBuffer(b)
    ptr = convert(Ptr{UInt8}, pointer(buf))
    len = sizeof(buf)
    arr = unsafe_wrap(Array, ptr, len)
    n = readbytes!(self, arr, len)
    return CPyLong_From(n)
end

@pyjlwrapfunc function bufferedio_write(self, b::PyPtr)::PyPtr
    buf = PyBuffer(b)
    ptr = convert(Ptr{UInt8}, pointer(buf))
    len = sizeof(buf)
    unsafe_write(self, ptr, len)
    return CPyLong_From(len)
end

@pyjlwrapfunc function textio_write(self, x::PyPtr)::PyPtr
    y = CPyObject_Str(String, x)
    y===nothing && return C_NULL
    return CPyLong_From(write(self, y))
end

@pyjlwrapfunc function textio_get_encoding_utf8(self, ::Ptr{Cvoid})::PyPtr
    return CPyUnicode_From("utf-8")
end

@pyjlwrapfunc function textio_read(self, args::PyPtr)::PyPtr
    r = @CPyArg_ParseTuple(args, n::Int=-1)
    r===nothing && return C_NULL
    (n,) = r
    v = n<0 ? read(self) : read(self, n)
    return CPyUnicode_DecodeUTF8(v, length(v), C_NULL)
end

@pyjlwrapfunc function textio_readline(self, args::PyPtr)::PyPtr
    r = @CPyArg_ParseTuple(args, n::Int=-1)
    r===nothing && return C_NULL
    (n,) = r
    s = readline(self, keep=true)
    return CPyUnicode_From(s)
end

@pyjlwrapfunc function get_name_string(o, ::Ptr{Cvoid})::PyPtr
    return CPyUnicode_From(string(o))
end

@pyjlwrapfunc function get_name_nameof(o, ::Ptr{Cvoid})::PyPtr
    return CPyUnicode_From(nameof(o))
end

@pyjlwrapfunc function get_doc(o, ::Ptr{Cvoid})::PyPtr
    return CPyUnicode_From(string(Docs.doc(o)))
end

function _pyjlwrap_get_none(o::PyPtr, ::Ptr{Cvoid})::PyPtr
    return CPy_None_NewRef()
end

function pyjlwrap_init_type!(
    t::Ref{CPyTypeObject};
    name = missing,
    extraflags = zero(Py_TPFLAGS_BASETYPE),
    tp_name = name===missing ? missing : "PyCall.$name",
    tp_basicsize = sizeof(CPyJlWrapObject),
    tp_new = @pyglobal(:PyType_GenericNew),
    tp_flags = pyjlwraptype_defaultflags() | extraflags,
    opts...)
    tp_name === missing && error("name required")
    t[] = CPyTypeObject(; tp_name=tp_name, tp_basicsize=tp_basicsize, tp_new=tp_new, tp_flags=tp_flags, opts...)
    @pycheckz CPyType_Ready(t)
    CPy_IncRef(t)
    t
end

##########################################################
# jlwrap types

# base type
const CPyJlWrap_Type = Ref(CPyTypeObject_NULL)
# for iterators (a tuple `(x, iterate(x))`)
# abstract base classes from `numbers`
const CPyJlWrapNumber_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapComplex_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapReal_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapRational_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapIntegral_Type = Ref(CPyTypeObject_NULL)
# abstract base classes from `collections.abc`
const CPyJlWrapContainer_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapIterable_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapIterator_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapCallable_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapFunction_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapCollection_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapSequence_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapMutableSequence_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapByteString_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapSet_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapMutableSet_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapMapping_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapJlNamedTuple_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapMutableMapping_Type = Ref(CPyTypeObject_NULL)
# abstract base classes from `io`
const CPyJlWrapIOBase_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapRawIO_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapBufferedIO_Type = Ref(CPyTypeObject_NULL)
const CPyJlWrapTextIO_Type = Ref(CPyTypeObject_NULL)

const CPyNumberMethods_default = Ref(CPyNumberMethods_NULL)
const CPyMappingMethods_default = Ref(CPyMappingMethods_NULL)
const CPySequenceMethods_oneup = Ref(CPySequenceMethods_NULL)
const CPyMappingMethods_oneup = Ref(CPyMappingMethods_NULL)
const CPyMappingMethods_namedtuple = Ref(CPyMappingMethods_NULL)

const have_stackless_extension = Ref(false)

function pyjlwraptype_defaultflags()
    flags =
        if pyversion.major ≥ 3
             Py_TPFLAGS_HAVE_VERSION_TAG
        else
            Py_TPFLAGS_HAVE_GETCHARBUFFER |
            Py_TPFLAGS_HAVE_SEQUENCE_IN |
            Py_TPFLAGS_HAVE_INPLACEOPS |
            Py_TPFLAGS_HAVE_RICHCOMPARE |
            Py_TPFLAGS_HAVE_WEAKREFS |
            Py_TPFLAGS_HAVE_ITER |
            Py_TPFLAGS_HAVE_CLASS |
            Py_TPFLAGS_HAVE_INDEX
        end
    if have_stackless_extension[]
        flags |= Py_TPFLAGS_HAVE_STACKLESS_EXTENSION
    end
    flags
end

function pyjlwrap_init()

    empty!(GLOBAL_CACHE)

    # detect at runtime whether we are using Stackless Python
    try
        pyimport("stackless")
        have_stackless_extension[] = true
    catch
        have_stackless_extension[] = false
    end

    CPyNumberMethods_default[] = CPyNumberMethods(
        nb_bool = @cfunction(_pyjlwrap_istrue, Cint, (PyPtr,)),
        nb_int = @cfunction(_pyjlwrap_int, PyPtr, (PyPtr,)),
        nb_float = @cfunction(_pyjlwrap_float, PyPtr, (PyPtr,)),
        nb_negative = @cfunction(_pyjlwrap_negative, PyPtr, (PyPtr,)),
        nb_positive = @cfunction(_pyjlwrap_positive, PyPtr, (PyPtr,)),
        nb_absolute = @cfunction(_pyjlwrap_absolute, PyPtr, (PyPtr,)),
        nb_invert = @cfunction(_pyjlwrap_invert, PyPtr, (PyPtr,)),
        nb_add = @cfunction(_pyjlwrap_add, PyPtr, (PyPtr, PyPtr)),
        nb_subtract = @cfunction(_pyjlwrap_subtract, PyPtr, (PyPtr, PyPtr)),
        nb_multiply = @cfunction(_pyjlwrap_multiply, PyPtr, (PyPtr, PyPtr)),
        nb_remainder = @cfunction(_pyjlwrap_remainder, PyPtr, (PyPtr, PyPtr)),
        nb_lshift = @cfunction(_pyjlwrap_lshift, PyPtr, (PyPtr, PyPtr)),
        nb_rshift = @cfunction(_pyjlwrap_rshift, PyPtr, (PyPtr, PyPtr)),
        nb_and = @cfunction(_pyjlwrap_and, PyPtr, (PyPtr, PyPtr)),
        nb_xor = @cfunction(_pyjlwrap_xor, PyPtr, (PyPtr, PyPtr)),
        nb_or = @cfunction(_pyjlwrap_or, PyPtr, (PyPtr, PyPtr)),
        nb_floordivide = @cfunction(_pyjlwrap_floordivide, PyPtr, (PyPtr, PyPtr)),
        nb_truedivide = @cfunction(_pyjlwrap_truedivide, PyPtr, (PyPtr, PyPtr)),
        nb_power = @cfunction(_pyjlwrap_power, PyPtr, (PyPtr, PyPtr, PyPtr)),
    )

    CPyMappingMethods_default[] = CPyMappingMethods(
        mp_length = @cfunction(_pyjlwrap_length, Cssize_t, (PyPtr,)),
        mp_subscript = @cfunction(_pyjlwrap_getitem, PyPtr, (PyPtr, PyPtr)),
        mp_ass_subscript = @cfunction(_pyjlwrap_setitem, Cint, (PyPtr, PyPtr, PyPtr)),
    )

    CPySequenceMethods_oneup[] = CPySequenceMethods(
        sq_length = @cfunction(_pyjlwrap_length, Cssize_t, (PyPtr,)),
        sq_item = @cfunction(_pyjlwrap_getitem_oneup, PyPtr, (PyPtr, Cssize_t)),
    )

    CPyMappingMethods_oneup[] = CPyMappingMethods(
        mp_length = @cfunction(_pyjlwrap_length, Cssize_t, (PyPtr,)),
        mp_subscript = @cfunction(_pyjlwrap_getitem_oneup, PyPtr, (PyPtr, PyPtr)),
        mp_ass_subscript = @cfunction(_pyjlwrap_setitem_oneup, Cint, (PyPtr, PyPtr, PyPtr)),
    )

    CPyMappingMethods_namedtuple[] = CPyMappingMethods(
        mp_subscript = @cfunction(_pyjlwrap_getitem_namedtuple, PyPtr, (PyPtr, PyPtr)),
    )

    pyjlwrap_init_type!(CPyJlWrap_Type,
        name = "JlWrap",
        extraflags = Py_TPFLAGS_BASETYPE,
        tp_members = [
            CPyMemberDef(name="__julia_value", typ=T_PYSSIZET, offset=fieldoffset(CPyJlWrapObject, 4), flags=READONLY, doc="Julia jl_value_t* (Any object)"),
        ],
        tp_dealloc = @cfunction(_pyjlwrap_dealloc, Cvoid, (PyPtr,)),
        tp_repr = @cfunction(_pyjlwrap_repr, PyPtr, (PyPtr,)),
        tp_str = @cfunction(_pyjlwrap_str, PyPtr, (PyPtr,)),
        tp_call = @cfunction(_pyjlwrap_call, PyPtr, (PyPtr,PyPtr,PyPtr)),
        tp_getattro = @cfunction(_pyjlwrap_getattr, PyPtr, (PyPtr,PyPtr)),
        tp_setattro = @cfunction(_pyjlwrap_setattr, Cint, (PyPtr,PyPtr,PyPtr)),
        tp_iter = @cfunction(_pyjlwrap_getiter, PyPtr, (PyPtr,)),
        tp_hash = sizeof(Py_hash_t) < sizeof(Int) ?
            @cfunction(_pyjlwrap_hash32, UInt32, (PyPtr,)) :
            @cfunction(_pyjlwrap_hash, UInt, (PyPtr,)),
        tp_weaklistoffset = fieldoffset(CPyJlWrapObject, 3),
        tp_richcompare = @cfunction(_pyjlwrap_richcompare, PyPtr, (PyPtr,PyPtr,Cint)),
        tp_as_number = CPyNumberMethods_default[],
        tp_as_mapping = CPyMappingMethods_default[],
        tp_methods = [
            CPyMethodDef(name="__dir__", meth=@cpymethod(_pyjlwrap_dir), flags=METH_NOARGS),
            CPyMethodDef(name="__complex__", meth=@cpymethod(_pyjlwrap_complex), flags=METH_NOARGS),
        ],
        tp_getset = [
            # CPyGetSetDef(name="__doc__", get=@cpygetfunc(_pyjlwrap_get_doc)),
            CPyGetSetDef(name="__name__", get=@cpygetfunc(_pyjlwrap_get_name_string)),
        ],
    )
    

    # ABSTRACT BASE CLASSES FROM `numbers`

    pyjlwrap_init_type!(CPyJlWrapNumber_Type,
        name = "JlWrapNumber",
        tp_base = CPyJlWrap_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapComplex_Type,
        name = "JlWrapComplex",
        tp_base = CPyJlWrapNumber_Type,
        tp_getset = [
            CPyGetSetDef(name="real", get=@cpygetfunc(_pyjlwrap_get_real)),
            CPyGetSetDef(name="imag", get=@cpygetfunc(_pyjlwrap_get_imag)),
        ],
        tp_methods = [
            CPyMethodDef(name="conjugate", meth=@cpymethod(_pyjlwrap_conjugate), flags=METH_NOARGS),
        ]
    )

    pyjlwrap_init_type!(CPyJlWrapReal_Type,
        name = "JlWrapReal",
        tp_base = CPyJlWrapComplex_Type,
        tp_methods = [
            CPyMethodDef(name="trunc", meth=@cpymethod(_pyjlwrap_trunc), flags=METH_NOARGS),
            CPyMethodDef(name="round", meth=@cpymethod(_pyjlwrap_round), flags=METH_NOARGS),
            CPyMethodDef(name="floor", meth=@cpymethod(_pyjlwrap_floor), flags=METH_NOARGS),
            CPyMethodDef(name="ceil", meth=@cpymethod(_pyjlwrap_ceil), flags=METH_NOARGS),
        ]
    )

    pyjlwrap_init_type!(CPyJlWrapRational_Type,
        name = "JlWrapRational",
        tp_base = CPyJlWrapReal_Type,
        tp_getset = [
            CPyGetSetDef(name="numerator", get=@cpygetfunc(_pyjlwrap_get_numerator)),
            CPyGetSetDef(name="denominator", get=@cpygetfunc(_pyjlwrap_get_denominator)),
        ],
    )

    pyjlwrap_init_type!(CPyJlWrapIntegral_Type,
        name = "JlWrapIntegral",
        tp_base = CPyJlWrapRational_Type,
    )

    # ABSTRACT BASE CLASSES FROM `collections.abc`

    pyjlwrap_init_type!(CPyJlWrapIterable_Type,
        name = "JlWrapIterable",
        tp_base = CPyJlWrap_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapIterator_Type,
        name = "JlWrapIterator",
        tp_base = CPyJlWrap_Type,
        tp_iter = @cfunction(pyincref_, PyPtr, (PyPtr,)),
        tp_iternext = @cfunction(_pyjlwrap_iternext, PyPtr, (PyPtr,)),
    )

    pyjlwrap_init_type!(CPyJlWrapCallable_Type,
        name = "JlWrapCallable",
        tp_base = CPyJlWrap_Type,
        tp_getset = [
            CPyGetSetDef(name="__qualname__", get=@cpygetfunc(_pyjlwrap_get_none)),
            CPyGetSetDef(name="__module__", get=@cpygetfunc(_pyjlwrap_get_none)),
            CPyGetSetDef(name="__closure__", get=@cpygetfunc(_pyjlwrap_get_none)),
        ],
    )

    pyjlwrap_init_type!(CPyJlWrapFunction_Type,
        name = "JlWrapFunction",
        tp_base = CPyJlWrapCallable_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapContainer_Type,
        name = "JlWrapContainer",
        tp_base = CPyJlWrap_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapCollection_Type,
        name = "JlWrapCollection",
        tp_base = CPyJlWrapIterable_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapSequence_Type,
        name = "PyCall.JlWrapSequence",
        tp_base = CPyJlWrapCollection_Type,
        tp_as_sequence = CPySequenceMethods_oneup[],
        tp_as_mapping = CPyMappingMethods_oneup[],
    )

    pyjlwrap_init_type!(CPyJlWrapMutableSequence_Type,
        name = "JlWrapMutableSequence",
        tp_base = CPyJlWrapSequence_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapByteString_Type,
        name = "JlWrapByteString",
        tp_base = CPyJlWrapSequence_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapSet_Type,
        name = "JlWrapSet",
        tp_base = CPyJlWrapCollection_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapMutableSet_Type,
        name = "JlWrapMutableSet",
        tp_base = CPyJlWrapSet_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapMapping_Type,
        name = "JlWrapMapping",
        tp_base = CPyJlWrapCollection_Type,
        tp_as_mapping = CPyMappingMethods_default[],
        tp_iter = @cfunction(_pyjlwrap_getiter_keys, PyPtr, (PyPtr,)),        
    )

    pyjlwrap_init_type!(CPyJlWrapJlNamedTuple_Type,
        name = "JlWrapJlNamedTuple",
        tp_base = CPyJlWrapMapping_Type,
        tp_as_sequence = CPySequenceMethods_oneup[],
        tp_as_mapping = CPyMappingMethods_namedtuple[],
    )

    pyjlwrap_init_type!(CPyJlWrapMutableMapping_Type,
        name = "JlWrapMutableMapping",
        tp_base = CPyJlWrapMapping_Type,
    )

    # ABSTRACT BASE CLASSES FROM `io`

    pyjlwrap_init_type!(CPyJlWrapIOBase_Type,
        name = "JlWrapIOBase",
        tp_base = CPyJlWrap_Type,
        tp_iter = @cfunction(_pyjlwrap_getiter_lines, PyPtr, (PyPtr,)),
        tp_methods = [
            CPyMethodDef(name="close", meth=@cpymethod(_pyjlwrap_io_close), flags=METH_NOARGS),
            CPyMethodDef(name="fileno", meth=@cpymethod(_pyjlwrap_io_fileno), flags=METH_NOARGS),
            CPyMethodDef(name="flush", meth=@cpymethod(_pyjlwrap_io_flush), flags=METH_NOARGS),
            CPyMethodDef(name="isatty", meth=@cpymethod(_pyjlwrap_io_isatty), flags=METH_NOARGS),
            CPyMethodDef(name="readable", meth=@cpymethod(_pyjlwrap_io_readable), flags=METH_NOARGS),
            CPyMethodDef(name="seek", meth=@cpymethod(_pyjlwrap_io_seek), flags=METH_VARARGS),
            CPyMethodDef(name="seekable", meth=@cpymethod(_pyjlwrap_io_seekable), flags=METH_NOARGS),
            CPyMethodDef(name="tell", meth=@cpymethod(_pyjlwrap_io_tell), flags=METH_NOARGS),
            CPyMethodDef(name="truncate", meth=@cpymethod(_pyjlwrap_io_truncate), flags=METH_VARARGS),
            CPyMethodDef(name="writable", meth=@cpymethod(_pyjlwrap_io_writable), flags=METH_NOARGS),
        ],
        tp_getset = [
            CPyGetSetDef(name="closed", get=@cpygetfunc(_pyjlwrap_io_get_closed)),
        ],
    )

    pyjlwrap_init_type!(CPyJlWrapRawIO_Type,
        name = "JlWrapRawIO",
        tp_base = CPyJlWrapIOBase_Type,
    )

    pyjlwrap_init_type!(CPyJlWrapBufferedIO_Type,
        name = "JlWrapBufferedIO",
        tp_base = CPyJlWrapIOBase_Type,
        tp_methods = [
            CPyMethodDef(name="read", meth=@cpymethod(_pyjlwrap_bufferedio_read), flags=METH_VARARGS),
            CPyMethodDef(name="readinto", meth=@cpymethod(_pyjlwrap_bufferedio_readinto), flags=METH_O),
            CPyMethodDef(name="write", meth=@cpymethod(_pyjlwrap_bufferedio_write), flags=METH_O),
        ],
    )

    pyjlwrap_init_type!(CPyJlWrapTextIO_Type,
        name = "JlWrapTextIO",
        tp_base = CPyJlWrapIOBase_Type,
        tp_methods = [
            CPyMethodDef(name="read", meth=@cpymethod(_pyjlwrap_textio_read), flags=METH_VARARGS),
            CPyMethodDef(name="readline", meth=@cpymethod(_pyjlwrap_textio_readline), flags=METH_VARARGS),
            CPyMethodDef(name="write", meth=@cpymethod(_pyjlwrap_textio_write), flags=METH_O),
        ],
        tp_getset = [
            CPyGetSetDef(name="encoding", get=@cpygetfunc(_pyjlwrap_textio_get_encoding_utf8))
        ],
    )

    # register with abstract base classes
    m = pyimport("numbers")
    m.Number.register(CPyJlWrapNumber_Type)
    m.Complex.register(CPyJlWrapComplex_Type)
    m.Real.register(CPyJlWrapReal_Type)
    m.Rational.register(CPyJlWrapRational_Type)
    m.Integral.register(CPyJlWrapIntegral_Type)

    m = pyimport("collections.abc")
    m.Iterable.register(CPyJlWrapIterable_Type)
    m.Iterator.register(CPyJlWrapIterator_Type)
    m.Callable.register(CPyJlWrapCallable_Type)
    m.Container.register(CPyJlWrapContainer_Type)
    m.Collection.register(CPyJlWrapCollection_Type)
    m.Sequence.register(CPyJlWrapSequence_Type)
    m.MutableSequence.register(CPyJlWrapMutableSequence_Type)
    m.ByteString.register(CPyJlWrapByteString_Type)
    m.Set.register(CPyJlWrapSet_Type)
    m.MutableSet.register(CPyJlWrapMutableSet_Type)
    m.Mapping.register(CPyJlWrapMapping_Type)
    m.MutableMapping.register(CPyJlWrapMutableMapping_Type)

    m = pyimport("io")
    m.IOBase.register(CPyJlWrapIOBase_Type)
    m.RawIOBase.register(CPyJlWrapRawIO_Type)
    m.TextIOBase.register(CPyJlWrapTextIO_Type)

end








##########################################################
# constructors for specific types

CPyJlWrap_From(x) = CPyJlWrap_New(CPyJlWrap_Type, x)
CPyJlWrap_From(x::Union{AbstractDict,AbstractArray,AbstractSet,NamedTuple,Tuple}) = CPyJlWrapIterable_From(x)
CPyJlWrap_From(x::Number) = CPyJlWrapNumber_From(x)
CPyJlWrap_From(x::IO) = CPyJlWrapIO_From(x)
CPyJlWrap_From(x::Union{Function,Type}) = CPyJlWrapCallable_From(x)

CPyJlWrapIterator_From(o) =
    let it = iterate(o)
        CPyJlWrap_New(CPyJlWrapIterator_Type, (o, Ref{Any}(it)))
    end

CPyJlWrapNumber_From(x) = CPyJlWrap_New(CPyJlWrapNumber_Type, x)
CPyJlWrapNumber_From(x::Complex) = CPyJlWrapComplex_From(x)
CPyJlWrapNumber_From(x::Real) = CPyJlWrapReal_From(x)

CPyJlWrapComplex_From(x) = CPyJlWrap_New(CPyJlWrapComplex_Type, x)
CPyJlWrapComplex_From(x::Real) = CPyJlWrapReal_From(x)

CPyJlWrapReal_From(x) = CPyJlWrap_New(CPyJlWrapReal_Type, x)
CPyJlWrapReal_From(x::Integer) = CPyJlWrapIntegral_From(x)
CPyJlWrapReal_From(x::Rational) = CPyJlWrapRational_From(x)

CPyJlWrapRational_From(x) = CPyJlWrap_New(CPyJlWrapRational_Type, x)
CPyJlWrapRational_From(x::Integer) = CPyJlWrapIntegral_From(x)

CPyJlWrapIntegral_From(x) = CPyJlWrap_New(CPyJlWrapIntegral_Type, x)

CPyJlWrapIterable_From(o) = CPyJlWrap_New(CPyJlWrapIterable_Type, o)
CPyJlWrapIterable_From(o::Union{AbstractDict,AbstractArray,AbstractSet,NamedTuple,Tuple}) = CPyJlWrapCollection_From(o)

CPyJlWrapCallable_From(o) = CPyJlWrap_New(CPyJlWrapCallable_Type, o)
CPyJlWrapCallable_From(o::Union{Function,Type}) = CPyJlWrapFunction_From(o)

CPyJlWrapFunction_From(o) = CPyJlWrap_New(CPyJlWrapFunction_Type, o)

CPyJlWrapCollection_From(o) = CPyJlWrap_New(CPyJlWrapCollection_Type, o)
CPyJlWrapCollection_From(o::Union{Tuple,AbstractArray}) = CPyJlWrapSequence_From(o)
CPyJlWrapCollection_From(o::AbstractSet) = CPyJlWrapSet_From(o)
CPyJlWrapCollection_From(o::Union{AbstractDict,NamedTuple}) = CPyJlWrapMapping_From(o)

CPyJlWrapSequence_From(o) = CPyJlWrap_New(CPyJlWrapSequence_Type, o)
CPyJlWrapSequence_From(o::AbstractArray) = CPyJlWrapMutableSequence_From(o)

CPyJlWrapMutableSequence_From(o) = CPyJlWrap_New(CPyJlWrapMutableSequence_Type, o)

CPyJlWrapMapping_From(o) = CPyJlWrap_New(CPyJlWrapMapping_Type, o)
CPyJlWrapMapping_From(o::Base.ImmutableDict) = CPyJlWrap_New(CPyJlWrapMapping_Type, o)
CPyJlWrapMapping_From(o::AbstractDict) = CPyJlWrapMutableMapping_From(o)
CPyJlWrapMapping_From(o::NamedTuple) = CPyJlWrapJlNamedTuple_From(o)

CPyJlWrapJlNamedTuple_From(o) = CPyJlWrap_New(CPyJlWrapJlNamedTuple_Type, o)

CPyJlWrapMutableMapping_From(o) = CPyJlWrap_New(CPyJlWrapMutableMapping_Type, o)

CPyJlWrapSet_From(o) = CPyJlWrap_New(CPyJlWrapSet_Type, o)
CPyJlWrapSet_From(o::AbstractSet) = CPyJlWrapMutableSet_From(o)

CPyJlWrapMutableSet_From(o) = CPyJlWrap_New(CPyJlWrapMutableSet_Type, o)

CPyJlWrapIO_From(o) = CPyJlWrap_New(CPyJlWrapIOBase_Type, o)
CPyJlWrapIO_From(o::IO) = CPyJlWrapBufferedIO_From(o)

CPyJlWrapBufferedIO_From(o) = CPyJlWrap_New(CPyJlWrapBufferedIO_Type, o)

CPyJlWrapRawIO_From(o) = CPyJlWrap_New(CPyJlWrapRawIO_Type, o)

CPyJlWrapTextIO_From(o) = CPyJlWrap_New(CPyJlWrapTextIO_Type, o)



export pyjlwrap, pyjlwrap_textio, pyjlwrap_rawio, pyjlwrap_bufferedio
pyjlwrap(x) = PyObject(CPyJlWrap_From(x))
pyjlwrap_rawio(x) = PyObject(CPyJlWrapRawIO_From(x))
pyjlwrap_textio(x) = PyObject(CPyJlWrapTextIO_From(x))
pyjlwrap_bufferedio(x) = PyObject(CPyJlWrapBufferedIO_From(x))




#########################################################################
# Precompilation: just an optimization to speed up initialization.
# Here, we precompile functions that are passed to cfunction by __init__,
# for the reasons described in JuliaLang/julia#12256.
precompile(_pyjlwrap_call, (PyPtr,PyPtr,PyPtr))
precompile(_pyjlwrap_dealloc, (PyPtr,))
precompile(_pyjlwrap_repr, (PyPtr,))
precompile(_pyjlwrap_hash, (PyPtr,))
precompile(_pyjlwrap_hash32, (PyPtr,))

