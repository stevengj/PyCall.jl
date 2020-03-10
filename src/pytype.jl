# Defining new Python types from Julia (ugly simulation of C headers)

################################################################
# Python expects the PyMethodDef and similar strings to be constants,
# so we define anonymous globals to hold them, returning the pointer
const permanent_strings = String[]
function gstring_ptr(s::AbstractString)
    g = String(s)
    push!(permanent_strings, g)
    unsafe_convert(Ptr{UInt8}, g)
end
gstring_ptr(s::Ptr) = convert(Ptr{UInt8}, s)

gstring_ptr_ornull(s::AbstractString) =
    isempty(s) ? NULL_UInt8_Ptr : gstring_ptr(s)
gstring_ptr_ornull(s::Ptr) = gstring_ptr(s)

################################################################
# mirror of Python API types and constants from methodobject.h



pymethoddef(name=C_NULL, meth=C_NULL, flags=0)

struct PyMethodDef
    ml_name::Ptr{UInt8}
    ml_meth::Ptr{Cvoid}
    ml_flags::Cint
    ml_doc::Ptr{UInt8}
    function PyMethodDef(name=C_NULL, meth=C_NULL, flags=0, doc=C_NULL)
        new(gstring_ptr(name), convert(Ptr{Cvoid}, meth), convert(Cint, flags), gstring_ptr_ornull(doc))
    end
end

const NULL_UInt8_Ptr = convert(Ptr{UInt8}, C_NULL)

################################################################
# mirror of Python API types and constants from descrobject.h

struct PyGetSetDef
    name::Ptr{UInt8}
    get::Ptr{Cvoid}
    set::Ptr{Cvoid} # may be NULL for read-only members
    doc::Ptr{UInt8} # may be NULL
    closure::Ptr{Cvoid} # pass-through thunk, may be NULL
    function PyGetSetDef(_name=C_NULL, _get=C_NULL, _set=C_NULL, _doc=C_NULL,_closure=C_NULL; name=_name, get=_get, set=_set, doc=_doc, closure=_closure)
        new(gstring_ptr(name), convert(Ptr{Cvoid}, get), convert(Ptr{Cvoid}, set), gstring_ptr_ornull(doc), convert(Ptr{Cvoid}, closure))
    end
end


################################################################
# from Python structmember.h:

# declare immutable because we need a C-like array of these
struct PyMemberDef
    name::Ptr{UInt8}
    typ::Cint
    offset::Int # warning: was Cint for Python <= 2.4
    flags::Cint
    doc::Ptr{UInt8}
    function PyMemberDef(name=C_NULL,typ=0,offset=0,flags=0,doc=C_NULL)
        new(gstring_ptr(name),
            convert(Cint,typ),
            convert(Int,offset),
            convert(Cint,flags),
            gstring_ptr_ornull(doc))
    end
end

################################################################
# Mirror of PyNumberMethods in Python object.h

const PyNumberMethods_fields = [
     (:nb_add, Ptr{Cvoid}, C_NULL),
     (:nb_subtract, Ptr{Cvoid}, C_NULL),
     (:nb_multiply, Ptr{Cvoid}, C_NULL),
     (:nb_remainder, Ptr{Cvoid}, C_NULL),
     (:nb_divmod, Ptr{Cvoid}, C_NULL),
     (:nb_power, Ptr{Cvoid}, C_NULL),
     (:nb_negative, Ptr{Cvoid}, C_NULL),
     (:nb_positive, Ptr{Cvoid}, C_NULL),
     (:nb_absolute, Ptr{Cvoid}, C_NULL),
     (:nb_bool, Ptr{Cvoid}, C_NULL),
     (:nb_invert, Ptr{Cvoid}, C_NULL),
     (:nb_lshift, Ptr{Cvoid}, C_NULL),
     (:nb_rshift, Ptr{Cvoid}, C_NULL),
     (:nb_and, Ptr{Cvoid}, C_NULL),
     (:nb_xor, Ptr{Cvoid}, C_NULL),
     (:nb_or, Ptr{Cvoid}, C_NULL),
     (:nb_int, Ptr{Cvoid}, C_NULL),
     (:nb_reserved, Ptr{Cvoid}, C_NULL),
     (:nb_float, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_add, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_subtract, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_multiply, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_remainder, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_power, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_lshift, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_rshift, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_and, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_xor, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_or, Ptr{Cvoid}, C_NULL),
     (:nb_floordivide, Ptr{Cvoid}, C_NULL),
     (:nb_truedivide, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_floordivide, Ptr{Cvoid}, C_NULL),
     (:nb_inplace_truedivide, Ptr{Cvoid}, C_NULL),
     (:nb_index, Ptr{Cvoid}, C_NULL),
     (:nb_matrixmultiply, Ptr{Cvoid}, C_NULL),
     (:nb_imatrixmultiply, Ptr{Cvoid}, C_NULL),
]

@eval struct PyNumberMethods
    $([:($n::$t) for (n,t,d) in PyNumberMethods_fields]...)
    PyNumberMethods(; $([Expr(:kw, n, d) for (n,t,d) in PyNumberMethods_fields]...)) =
        new($([:(convert($t, $n)) for (n,t,d) in PyNumberMethods_fields]...))
end


################################################################
# Mirror of PySequenceMethods in Python object.h

const PySequenceMethods_fields = [
    (:sq_length, Ptr{Cvoid}, C_NULL),
    (:sq_concat, Ptr{Cvoid}, C_NULL),
    (:sq_repeat, Ptr{Cvoid}, C_NULL),
    (:sq_item, Ptr{Cvoid}, C_NULL),
    (:was_sq_item, Ptr{Cvoid}, C_NULL),
    (:sq_ass_item, Ptr{Cvoid}, C_NULL),
    (:was_sq_ass_slice, Ptr{Cvoid}, C_NULL),
    (:sq_contains, Ptr{Cvoid}, C_NULL),
    (:sq_inplace_concat, Ptr{Cvoid}, C_NULL),
    (:sq_inplace_repeat, Ptr{Cvoid}, C_NULL),
]

@eval struct PySequenceMethods
    $([:($n :: $t) for (n,t,d) in PySequenceMethods_fields]...)
    PySequenceMethods(; $([Expr(:kw, n, d) for (n,t,d) in PySequenceMethods_fields]...)) =
        new($([:(convert($t, $n)) for (n,t,d) in PySequenceMethods_fields]...))
end


################################################################
# Mirror of PyMappingMethods in Python object.h

const PyMappingMethods_fields = [
    (:mp_length, Ptr{Cvoid}, C_NULL),
    (:mp_subscript, Ptr{Cvoid}, C_NULL),
    (:mp_ass_subscript, Ptr{Cvoid}, C_NULL),
]

@eval struct PyMappingMethods
    $([:($n :: $t) for (n,t,d) in PyMappingMethods_fields]...)
    PyMappingMethods(; $([Expr(:kw, n, d) for (n,t,d) in PyMappingMethods_fields]...)) =
        new($([:(convert($t, $n)) for (n,t,d) in PyMappingMethods_fields]...))
end

################################################################
# Mirror of PyTypeObject in Python object.h
#  -- assumes non-debugging Python build (no Py_TRACE_REFS)
#  -- most fields can default to 0 except where noted

PyTypeObject_defaultflags() =
    pyversion.major >= 3 ?
        (Py_TPFLAGS_HAVE_STACKLESS_EXTENSION[] |
         Py_TPFLAGS_HAVE_VERSION_TAG) :
        (Py_TPFLAGS_HAVE_GETCHARBUFFER |
         Py_TPFLAGS_HAVE_SEQUENCE_IN |
         Py_TPFLAGS_HAVE_INPLACEOPS |
         Py_TPFLAGS_HAVE_RICHCOMPARE |
         Py_TPFLAGS_HAVE_WEAKREFS |
         Py_TPFLAGS_HAVE_ITER |
         Py_TPFLAGS_HAVE_CLASS |
         Py_TPFLAGS_HAVE_STACKLESS_EXTENSION[] |
         Py_TPFLAGS_HAVE_INDEX)

const PyTypeObject_fields = [
    # PyObject_HEAD (for non-Py_TRACE_REFS build):
    (:ob_refcnt, Int, 0),
    (:ob_type, PyPtr, C_NULL),
    (:ob_size, Int, 0), # PyObject_VAR_HEAD, C_NULL

    # PyTypeObject fields:
    (:tp_name, Ptr{UInt8}, C_NULL), # required, should be in format "<module>.<name>"

    # warning: these two were Cint for Python <= 2.4
    (:tp_basicsize, Int, 0), # required, = sizeof(instance)
    (:tp_itemsize, Int, 0),

    (:tp_dealloc, Ptr{Cvoid}, C_NULL),
    (:tp_print, Ptr{Cvoid}, C_NULL),
    (:tp_getattr, Ptr{Cvoid}, C_NULL),
    (:tp_setattr, Ptr{Cvoid}, C_NULL),
    (:tp_compare, Ptr{Cvoid}, C_NULL),
    (:tp_repr, Ptr{Cvoid}, C_NULL),

    (:tp_as_number, Ptr{PyNumberMethods}, C_NULL),
    (:tp_as_sequence, Ptr{PySequenceMethods}, C_NULL),
    (:tp_as_mapping, Ptr{PyMappingMethods}, C_NULL),

    (:tp_hash, Ptr{Cvoid}, C_NULL),
    (:tp_call, Ptr{Cvoid}, C_NULL),
    (:tp_str, Ptr{Cvoid}, C_NULL),
    (:tp_getattro, Ptr{Cvoid}, C_NULL),
    (:tp_setattro, Ptr{Cvoid}, C_NULL),

    (:tp_as_buffer, Ptr{Cvoid}, C_NULL),

    (:tp_flags, Clong, 0), # Required, should default to Py_TPFLAGS_DEFAULT

    (:tp_doc, Ptr{UInt8}, C_NULL), # normally set in example code, but may be NULL

    (:tp_traverse, Ptr{Cvoid}, C_NULL),

    (:tp_clear, Ptr{Cvoid}, C_NULL),

    (:tp_richcompare, Ptr{Cvoid}, C_NULL),

    (:tp_weaklistoffset, Int, 0),

    # added in Python 2.2:
    (:tp_iter, Ptr{Cvoid}, C_NULL),
    (:tp_iternext, Ptr{Cvoid}, C_NULL),

    (:tp_methods, Ptr{PyMethodDef}, C_NULL),
    (:tp_members, Ptr{PyMemberDef}, C_NULL),
    (:tp_getset, Ptr{PyGetSetDef}, C_NULL),
    (:tp_base, Ptr{Cvoid}, C_NULL),

    (:tp_dict, PyPtr, C_NULL),
    (:tp_descr_get, Ptr{Cvoid}, C_NULL),
    (:tp_descr_set, Ptr{Cvoid}, C_NULL),
    (:tp_dictoffset, Int, 0),

    (:tp_init, Ptr{Cvoid}, C_NULL),
    (:tp_alloc, Ptr{Cvoid}, C_NULL),
    (:tp_new, Ptr{Cvoid}, C_NULL),
    (:tp_free, Ptr{Cvoid}, C_NULL),
    (:tp_is_gc, Ptr{Cvoid}, C_NULL),

    (:tp_bases, PyPtr, C_NULL),
    (:tp_mro, PyPtr, C_NULL),
    (:tp_cache, PyPtr, C_NULL),
    (:tp_subclasses, PyPtr, C_NULL),
    (:tp_weaklist, PyPtr, C_NULL),
    (:tp_del, Ptr{Cvoid}, C_NULL),

    # added in Python 2.6:
    (:tp_version_tag, Cuint, 0),

    # only used for COUNT_ALLOCS builds of Python
    (:tp_allocs, Int, 0),
    (:tp_frees, Int, 0),
    (:tp_maxalloc, Int, 0),
    (:tp_prev, Ptr{Cvoid}, C_NULL),
    (:tp_next, Ptr{Cvoid}, C_NULL),
]

@eval mutable struct PyTypeObject
    $([:($n :: $t) for (n,t,d) in PyTypeObject_fields]...)
    # cache of julia objects referenced by this type, to prevent them being garbage-collected
    jl_cache::Dict{Symbol,Any}

    function PyTypeObject(; unsafe_null=false, opts...)
        t = new($([:(convert($t, $d)) for (n,t,d) in PyTypeObject_fields]...), Dict{Symbol,Any}())
        unsafe_null ? t : PyTypeObject_init!(t; opts...)
    end
end

function PyTypeObject_init!(t::PyTypeObject; opts...)
    for (k, x) in pairs(opts)
        setproperty!(t, k, x)
    end
    t.tp_name == C_NULL && error("required: tp_name")
    t.tp_basicsize == 0 && !haskey(opts, :tp_basicsize) && error("required: tp_basicsize")
    t.tp_flags == 0 && !haskey(opts, :tp_flags) && (t.tp_flags = PyTypeObject_defaultflags())
    t.tp_new == C_NULL && !haskey(opts, :tp_new) && (t.tp_new = @pyglobal(:PyType_GenericNew))
    @pycheckz ccall((@pysym :PyType_Ready), Cint, (Ref{PyTypeObject},), t)
    ccall((@pysym :Py_IncRef), Cvoid, (Any,), t)
    return t
end

function Base.setproperty!(t::PyTypeObject, k::Symbol, x)
    if k == :tp_name && x isa AbstractString
        z = t.jl_cache[k] = Base.cconvert(Ptr{UInt8}, x)
        setfield!(t, k, unsafe_convert(Ptr{UInt8}, z))
    elseif k == :tp_as_number && x isa PyNumberMethods
        z = t.jl_cache[k] = Ref(x)
        setfield!(t, k, unsafe_convert(Ptr{PyNumberMethods}, z))
    elseif k == :tp_as_sequence && x isa PySequenceMethods
        z = t.jl_cache[k] = Ref(x)
        setfield!(t, k, unsafe_convert(Ptr{PySequenceMethods}, z))
    elseif k == :tp_as_mapping && x isa PyMappingMethods
        z = t.jl_cache[k] = Ref(x)
        setfield!(t, k, unsafe_convert(Ptr{PyMappingMethods}, z))
    elseif k == :tp_members && x isa AbstractVector{PyMemberDef}
        z = t.jl_cache[k] = push!(copy(convert(Vector{PyMemberDef}, x)), PyMemberDef())
        setfield!(t, k, pointer(z))
    elseif k == :tp_methods && x isa AbstractVector{PyMethodDef}
        z = t.jl_cache[k] = push!(copy(convert(Vector{PyMethodDef}, x)), PyMethodDef())
        setfield!(t, k, pointer(z))
    elseif k == :tp_getset && x isa AbstractVector{PyGetSetDef}
        z = t.jl_cache[k] = push!(copy(convert(Vector{PyGetSetDef}, x)), PyGetSetDef())
        setfield!(t, k, pointer(z))
    elseif k == :tp_dict && x isa NamedTuple
        d = t.jl_cache[k] = PyObject(@pycheckn ccall(@pysym(:PyDict_New), PyPtr, ()))
        for (k, v) in pairs(x)
            @pycheckz ccall(@pysym(:PyDict_SetItemString), Cint, (PyPtr, Cstring, PyPtr), d, string(k), PyObject(v))
        end
        setfield!(t, k, PyPtr(d))
    elseif k == :tp_base && x isa PyTypeObject
        t.jl_cache[k] = x
        setfield!(t, k, pointer_from_objref(x))
    else
        setfield!(t, k, convert(fieldtype(PyTypeObject, k), x))
    end
end

unsafe_pytype(o::PyPtr) =
    convert(Ptr{PyTypeObject}, unsafe_load(o).ob_type)

PyObject(t::PyTypeObject) = pyincref(convert(PyPtr, pointer_from_objref(t)))
