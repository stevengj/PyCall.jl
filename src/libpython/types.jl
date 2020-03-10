# Mirror of C PyObject struct (for non-debugging Python builds).
# We won't actually access these fields directly; we'll use the Python
# C API for everything.  However, we need to define a unique Ptr type
# for PyObject*, and we might as well define the actual struct layout
# while we're at it.
struct CPyObject
    ob_refcnt::Int
    ob_type::Ptr{Cvoid}
end

const PyPtr = Ptr{CPyObject} # type for PythonObject* in ccall
const PyPtr_NULL = PyPtr(C_NULL)

const sizeof_CPyObject_HEAD = sizeof(Int) + sizeof(PyPtr)

################################################################
# complex

struct CPy_complex
	real :: Cdouble
	imag :: Cdouble
end

################################################################
# buffer

struct CPy_buffer
    buf::Ptr{Cvoid}
    obj::PyPtr
    len::Cssize_t
    itemsize::Cssize_t

    readonly::Cint
    ndim::Cint
    format::Ptr{Cchar}
    shape::Ptr{Cssize_t}
    strides::Ptr{Cssize_t}
    suboffsets::Ptr{Cssize_t}

    # some opaque padding fields to account for differences between
    # Python versions (the structure changed in Python 2.7 and 3.3)
    internal0::Ptr{Cvoid}
    internal1::Ptr{Cvoid}
    internal2::Ptr{Cvoid}
end

const CPy_buffer_NULL = CPy_buffer(C_NULL, C_NULL, 0, 0, 0, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)

const PyBUF_SIMPLE    = convert(Cint, 0)
const PyBUF_WRITABLE  = convert(Cint, 0x0001)
const PyBUF_FORMAT    = convert(Cint, 0x0004)
const PyBUF_ND        = convert(Cint, 0x0008)
const PyBUF_STRIDES        = convert(Cint, 0x0010) | PyBUF_ND
const PyBUF_C_CONTIGUOUS   = convert(Cint, 0x0020) | PyBUF_STRIDES
const PyBUF_F_CONTIGUOUS   = convert(Cint, 0x0040) | PyBUF_STRIDES
const PyBUF_ANY_CONTIGUOUS = convert(Cint, 0x0080) | PyBUF_STRIDES
const PyBUF_INDIRECT       = convert(Cint, 0x0100) | PyBUF_STRIDES
const PyBUF_ND_STRIDED    = Cint(PyBUF_WRITABLE | PyBUF_FORMAT | PyBUF_ND |
                                 PyBUF_STRIDES)
const PyBUF_ND_CONTIGUOUS = PyBUF_ND_STRIDED | PyBUF_ANY_CONTIGUOUS

################################################################
# mirror of Python API types and constants from methodobject.h

struct CPyMethodDef
    ml_name::Ptr{UInt8}
    ml_meth::Ptr{Cvoid}
    ml_flags::Cint
    ml_doc::Ptr{UInt8}
end

const CPyMethodDef_NULL = CPyMethodDef(C_NULL, C_NULL, 0, C_NULL)

# A PyCFunction is a C function of the form
#     PyObject *func(PyObject *self, PyObject *args)
# or
#     PyObject *func(PyObject *self, PyObject *args, PyObject *kwargs)
# The first parameter is the "self" function for method, or
# for module functions it is the module object.  The second
# parameter is either a tuple of args (for METH_VARARGS),
# a single arg (for METH_O), or NULL (for METH_NOARGS).  func
# must return non-NULL (Py_None is okay) unless there was an
# error, in which case an exception must have been set.

# ml_flags should be one of:
const METH_VARARGS = 0x0001 # args are a tuple of arguments
const METH_KEYWORDS = 0x0002  # two arguments: the varargs and the kwargs
const METH_NOARGS = 0x0004  # no arguments (NULL argument pointer)
const METH_O = 0x0008       # single argument (not wrapped in tuple)

# not sure when these are needed:
const METH_CLASS = 0x0010 # for class methods
const METH_STATIC = 0x0020 # for static methods

################################################################
# mirror of Python API types and constants from descrobject.h

struct CPyGetSetDef
    name::Ptr{UInt8}
    get::Ptr{Cvoid}
    set::Ptr{Cvoid} # may be NULL for read-only members
    doc::Ptr{UInt8} # may be NULL
    closure::Ptr{Cvoid} # pass-through thunk, may be NULL
end

const CPyGetSetDef_NULL = CPyGetSetDef(C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)


################################################################
# from Python structmember.h:

# declare immutable because we need a C-like array of these
struct CPyMemberDef
    name::Ptr{UInt8}
    typ::Cint
    offset::Int # warning: was Cint for Python <= 2.4
    flags::Cint
    doc::Ptr{UInt8}
end

const CPyMemberDef_NULL = CPyMemberDef(C_NULL, 0, 0, 0, C_NULL)

# types:
const T_SHORT        =0
const T_INT          =1
const T_LONG         =2
const T_FLOAT        =3
const T_DOUBLE       =4
const T_STRING       =5
const T_OBJECT       =6
const T_CHAR         =7
const T_BYTE         =8
const T_UBYTE        =9
const T_USHORT       =10
const T_UINT         =11
const T_ULONG        =12
const T_STRING_INPLACE       =13
const T_BOOL         =14
const T_OBJECT_EX    =16
const T_LONGLONG     =17 # added in Python 2.5
const T_ULONGLONG    =18 # added in Python 2.5
const T_PYSSIZET     =19 # added in Python 2.6
const T_NONE         =20 # added in Python 3.0

# flags:
const READONLY = 1
const READ_RESTRICTED = 2
const PY_WRITE_RESTRICTED = 4
const RESTRICTED = (READ_RESTRICTED | PY_WRITE_RESTRICTED)

################################################################
# type-flag constants, from Python object.h:

# Python 2.7
const Py_TPFLAGS_HAVE_GETCHARBUFFER  = (0x00000001<<0)
const Py_TPFLAGS_HAVE_SEQUENCE_IN = (0x00000001<<1)
const Py_TPFLAGS_GC = 0 # was sometimes (0x00000001<<2) in Python <= 2.1
const Py_TPFLAGS_HAVE_INPLACEOPS = (0x00000001<<3)
const Py_TPFLAGS_CHECKTYPES = (0x00000001<<4)
const Py_TPFLAGS_HAVE_RICHCOMPARE = (0x00000001<<5)
const Py_TPFLAGS_HAVE_WEAKREFS = (0x00000001<<6)
const Py_TPFLAGS_HAVE_ITER = (0x00000001<<7)
const Py_TPFLAGS_HAVE_CLASS = (0x00000001<<8)
const Py_TPFLAGS_HAVE_INDEX = (0x00000001<<17)
const Py_TPFLAGS_HAVE_NEWBUFFER = (0x00000001<<21)
const Py_TPFLAGS_STRING_SUBCLASS       = (0x00000001<<27)

# Python 3.0+ has only these:
const Py_TPFLAGS_HEAPTYPE = (0x00000001<<9)
const Py_TPFLAGS_BASETYPE = (0x00000001<<10)
const Py_TPFLAGS_READY = (0x00000001<<12)
const Py_TPFLAGS_READYING = (0x00000001<<13)
const Py_TPFLAGS_HAVE_GC = (0x00000001<<14)
const Py_TPFLAGS_HAVE_VERSION_TAG   = (0x00000001<<18)
const Py_TPFLAGS_VALID_VERSION_TAG  = (0x00000001<<19)
const Py_TPFLAGS_IS_ABSTRACT = (0x00000001<<20)
const Py_TPFLAGS_INT_SUBCLASS         = (0x00000001<<23)
const Py_TPFLAGS_LONG_SUBCLASS        = (0x00000001<<24)
const Py_TPFLAGS_LIST_SUBCLASS        = (0x00000001<<25)
const Py_TPFLAGS_TUPLE_SUBCLASS       = (0x00000001<<26)
const Py_TPFLAGS_BYTES_SUBCLASS       = (0x00000001<<27)
const Py_TPFLAGS_UNICODE_SUBCLASS     = (0x00000001<<28)
const Py_TPFLAGS_DICT_SUBCLASS        = (0x00000001<<29)
const Py_TPFLAGS_BASE_EXC_SUBCLASS    = (0x00000001<<30)
const Py_TPFLAGS_TYPE_SUBCLASS        = (0x00000001<<31)

# only use this if we have the stackless extension
const Py_TPFLAGS_HAVE_STACKLESS_EXTENSION = (0x00000003<<15)

################################################################
# Mirror of PyNumberMethods in Python object.h

struct CPyNumberMethods
     nb_add::Ptr{Cvoid}
     nb_subtract::Ptr{Cvoid}
     nb_multiply::Ptr{Cvoid}
     nb_remainder::Ptr{Cvoid}
     nb_divmod::Ptr{Cvoid}
     nb_power::Ptr{Cvoid}
     nb_negative::Ptr{Cvoid}
     nb_positive::Ptr{Cvoid}
     nb_absolute::Ptr{Cvoid}
     nb_bool::Ptr{Cvoid}
     nb_invert::Ptr{Cvoid}
     nb_lshift::Ptr{Cvoid}
     nb_rshift::Ptr{Cvoid}
     nb_and::Ptr{Cvoid}
     nb_xor::Ptr{Cvoid}
     nb_or::Ptr{Cvoid}
     nb_int::Ptr{Cvoid}
     nb_reserved::Ptr{Cvoid}
     nb_float::Ptr{Cvoid}
     nb_inplace_add::Ptr{Cvoid}
     nb_inplace_subtract::Ptr{Cvoid}
     nb_inplace_multiply::Ptr{Cvoid}
     nb_inplace_remainder::Ptr{Cvoid}
     nb_inplace_power::Ptr{Cvoid}
     nb_inplace_lshift::Ptr{Cvoid}
     nb_inplace_rshift::Ptr{Cvoid}
     nb_inplace_and::Ptr{Cvoid}
     nb_inplace_xor::Ptr{Cvoid}
     nb_inplace_or::Ptr{Cvoid}
     nb_floordivide::Ptr{Cvoid}
     nb_truedivide::Ptr{Cvoid}
     nb_inplace_floordivide::Ptr{Cvoid}
     nb_inplace_truedivide::Ptr{Cvoid}
     nb_index::Ptr{Cvoid}
     nb_matrixmultiply::Ptr{Cvoid}
     nb_imatrixmultiply::Ptr{Cvoid}
end

const CPyNumberMethods_NULL = CPyNumberMethods(C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)

################################################################
# Mirror of PySequenceMethods in Python object.h

struct CPySequenceMethods
    sq_length::Ptr{Cvoid}
    sq_concat::Ptr{Cvoid}
    sq_repeat::Ptr{Cvoid}
    sq_item::Ptr{Cvoid}
    was_sq_item::Ptr{Cvoid}
    sq_ass_item::Ptr{Cvoid}
    was_sq_ass_slice::Ptr{Cvoid}
    sq_contains::Ptr{Cvoid}
    sq_inplace_concat::Ptr{Cvoid}
    sq_inplace_repeat::Ptr{Cvoid}
end

const CPySequenceMethods_NULL = CPySequenceMethods(C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)

################################################################
# Mirror of PyMappingMethods in Python object.h

struct CPyMappingMethods
    mp_length::Ptr{Cvoid}
    mp_subscript::Ptr{Cvoid}
    mp_ass_subscript::Ptr{Cvoid}
end

const CPyMappingMethods_NULL = CPyMappingMethods(C_NULL, C_NULL, C_NULL)

################################################################
# Mirror of PyTypeObject in Python object.h
#  -- assumes non-debugging Python build (no Py_TRACE_REFS)
#  -- most fields can default to 0 except where noted

struct CPyTypeObject
    # PyObject_HEAD (for non-Py_TRACE_REFS build):
    ob_refcnt::Int
    ob_type::PyPtr
    ob_size::Int # PyObject_VAR_HEAD, C_NULL

    # PyTypeObject fields:
    tp_name::Ptr{UInt8} # required, should be in format "<module>.<name>"

    # warning: these two were Cint for Python <= 2.4
    tp_basicsize::Int # required, = sizeof(instance)
    tp_itemsize::Int

    tp_dealloc::Ptr{Cvoid}
    tp_print::Ptr{Cvoid}
    tp_getattr::Ptr{Cvoid}
    tp_setattr::Ptr{Cvoid}
    tp_compare::Ptr{Cvoid}
    tp_repr::Ptr{Cvoid}

    tp_as_number::Ptr{CPyNumberMethods}
    tp_as_sequence::Ptr{CPySequenceMethods}
    tp_as_mapping::Ptr{CPyMappingMethods}

    tp_hash::Ptr{Cvoid}
    tp_call::Ptr{Cvoid}
    tp_str::Ptr{Cvoid}
    tp_getattro::Ptr{Cvoid}
    tp_setattro::Ptr{Cvoid}

    tp_as_buffer::Ptr{Cvoid}

    tp_flags::Clong # Required, should default to Py_TPFLAGS_DEFAULT

    tp_doc::Ptr{UInt8} # normally set in example code, but may be NULL

    tp_traverse::Ptr{Cvoid}

    tp_clear::Ptr{Cvoid}

    tp_richcompare::Ptr{Cvoid}

    tp_weaklistoffset::Int

    # added in Python 2.2:
    tp_iter::Ptr{Cvoid}
    tp_iternext::Ptr{Cvoid}

    tp_methods::Ptr{CPyMethodDef}
    tp_members::Ptr{CPyMemberDef}
    tp_getset::Ptr{CPyGetSetDef}
    tp_base::Ptr{Cvoid}

    tp_dict::PyPtr
    tp_descr_get::Ptr{Cvoid}
    tp_descr_set::Ptr{Cvoid}
    tp_dictoffset::Int

    tp_init::Ptr{Cvoid}
    tp_alloc::Ptr{Cvoid}
    tp_new::Ptr{Cvoid}
    tp_free::Ptr{Cvoid}
    tp_is_gc::Ptr{Cvoid}

    tp_bases::PyPtr
    tp_mro::PyPtr
    tp_cache::PyPtr
    tp_subclasses::PyPtr
    tp_weaklist::PyPtr
    tp_del::Ptr{Cvoid}

    # added in Python 2.6:
    tp_version_tag::Cuint

    # only used for COUNT_ALLOCS builds of Python
    tp_allocs::Int
    tp_frees::Int
    tp_maxalloc::Int
    tp_prev::Ptr{Cvoid}
    tp_next::Ptr{Cvoid}
end

const CPyTypeObject_NULL = CPyTypeObject(0, C_NULL, 0, C_NULL, 0, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, 0, C_NULL, C_NULL, C_NULL, C_NULL, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL, 0, 0, 0, 0, C_NULL, C_NULL)

################################################################
# datetime

struct CPyDateTime_CAPI
    # type objects:
    DateType::PyPtr
    DateTimeType::PyPtr
    TimeType::PyPtr
    DeltaType::PyPtr
    TZInfoType::PyPtr

    # singletons:
    @static if pyversion >= v"3.7"
        TimeZone_UTC::PyPtr
    end

    # function pointers:
    Date_FromDate::Ptr{Cvoid}
    DateTime_FromDateAndTime::Ptr{Cvoid}
    Time_FromTime::Ptr{Cvoid}
    Delta_FromDelta::Ptr{Cvoid}
    @static if pyversion >= v"3.7"
        TimeZone_FromTimeZone::Ptr{Cvoid}
    end
    DateTime_FromTimestamp::Ptr{Cvoid}
    Date_FromTimestamp::Ptr{Cvoid}
end

struct CPyDateTime_Delta
    # PyObject_HEAD (for non-Py_TRACE_REFS build):
    ob_refcnt::Int
    ob_type::PyPtr
    hashcode::Py_hash_t
    days::Cint
    seconds::Cint
    microseconds::Cint
end

struct CPyDateTime_Date
	ob_refcnt::Int
	ob_type::PyPtr
	hashcode::Py_hash_t
	hastzinfo::Cchar
	data::NTuple{4,Cuchar}
end

struct CPyDateTime_Time
	ob_refcnt::Int
	ob_type::PyPtr
	hashcode::Py_hash_t
	hastzinfo::Cchar
	data::NTuple{6,Cuchar}
	fold::Cuchar
	tzinfo::PyPtr
end

struct CPyDateTime_BaseDateTime
	ob_refcnt::Int
	ob_type::PyPtr
	hashcode::Py_hash_t
	hastzinfo::Cchar
	data::NTuple{10,Cuchar}
end

struct CPyDateTime_DateTime
	ob_refcnt::Int
	ob_type::PyPtr
	hashcode::Py_hash_t
	hastzinfo::Cchar
	data::NTuple{10,Cuchar}
	fold::Cuchar
	tzinfo::PyPtr
end

