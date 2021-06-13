# Julia wrappers around the NumPy API, as part of the PyCall package

#########################################################################
# Initialization (UGLY)

# Linking NumPy's C API from Julia requires some serious hackery,
# because NumPy does not export its symbols in the usual way for
# shared libraries.  Instead, it provides a Python variable
# numpy.core.multiarray._ARRAY_API that points to a lookup table of
# pointers to the API functions and global variables.  Moreover, the
# meaning of this table, along with a lot of other important
# constants, is defined in a C header file which changes between NumPy
# versions, so we need to do some regex parsing of this header file in
# order to extract the necessary information to call NumPy.  Ugly and
# mildly insane, but I don't see much alternative (at least to do this
# purely in Julia).
#
# The result of npy_api_initialize, below, is to produce the following
# tables of API pointers:
const npy_api = Dict{Symbol, Ptr{Cvoid}}()

# need a global to cache pyimport("numpy.core.multiarray"), in order
# to ensure the module is not garbage-collected as long as we are using it
# for the npy_api pointers.
const npy_multiarray = PyNULL()

npy_initialized = false # global to prevent multiple initializations

# Macro version of npyinitialize() to inline npy_initialized? check
macro npyinitialize()
    :(npy_initialized::Bool ? nothing : npyinitialize())
end

# numpy.number types, used to detect scalars for conversion routines
const npy_number = PyNULL()
const npy_integer = PyNULL()
const npy_floating = PyNULL()
const npy_complexfloating = PyNULL()
const npy_bool = PyNULL()

import LinearAlgebra # for MKL check

function npyinitialize()
    global npy_initialized

    if npy_initialized::Bool
        return
    end
    try
        copy!(npy_multiarray, pyimport("numpy.core.multiarray"))
    catch e
        error("numpy.core.multiarray required for multidimensional Array conversions - ", e)
    end
    if pyversion.major < 3
        PyArray_API = @pycheck ccall((@pysym :PyCObject_AsVoidPtr),
                                     Ptr{Ptr{Cvoid}}, (PyPtr,),
                                     npy_multiarray."_ARRAY_API")
    else
        PyArray_API = @pycheck ccall((@pysym :PyCapsule_GetPointer),
                                     Ptr{Ptr{Cvoid}}, (PyPtr,Ptr{Cvoid}),
                                     npy_multiarray."_ARRAY_API", C_NULL)
    end

    numpy = pyimport("numpy")

    # emit a warning if both Julia and NumPy are linked with MKL (#433)
    if VERSION < v"1.7"
        julia_compiled_with_mkl = LinearAlgebra.BLAS.vendor() === :mkl
    else
        julia_compiled_with_mkl = :mkl in LinearAlgebra.BLAS.get_config().build_flags
    end
    if julia_compiled_with_mkl &&
       LinearAlgebra.BLAS.BlasInt === Int64 && hasproperty(numpy, "__config__")
        config = numpy."__config__"
        if hasproperty(config, "blas_opt_info")
            blaslibs = get(config."blas_opt_info", Vector{String}, "libraries", String[])
            if any(s -> occursin("mkl", lowercase(s)), blaslibs)
                @warn "both Julia and NumPy are linked with MKL, which may cause conflicts and crashes (#433)."
            end
        end
    end

    # directory for numpy include files to parse
    inc = pycall(numpy."get_include", AbstractString)

    # numpy.number types
    copy!(npy_number, numpy."number")
    copy!(npy_integer, numpy."integer")
    copy!(npy_floating, numpy."floating")
    copy!(npy_complexfloating, numpy."complexfloating")
    copy!(npy_bool, numpy."bool_")

    # Parse __multiarray_api.h to obtain length and meaning of PyArray_API
    try
        hdrfile = open(joinpath(inc, "numpy", "__multiarray_api.h"))
        hdr = read(hdrfile, String)
        close(hdrfile)
    catch e
        error("could not read __multiarray_api.h to parse PyArray_API ", e)
    end
    hdr = replace(hdr, r"\\\s*\n"=>" "); # rm backslashed newlines
    r = r"^#define\s+([A-Za-z]\w*)\s+\(.*\bPyArray_API\s*\[\s*([0-9]+)\s*\]\s*\)\s*$"m # regex to match #define PyFoo (... PyArray_API[nnn])
    PyArray_API_length = 0
    for m in eachmatch(r, hdr) # search for max index into PyArray_API
        PyArray_API_length = max(PyArray_API_length, parse(Int, m.captures[2])+1)
    end
    API = unsafe_wrap(Array, PyArray_API, (PyArray_API_length,))
    for m in eachmatch(r, hdr) # build npy_api table
        npy_api[Symbol(m.captures[1])] = API[parse(Int, m.captures[2])+1]
    end
    if !haskey(npy_api, :PyArray_New)
        error("failure parsing NumPy PyArray_API symbol table")
    end

    npy_initialized = true
    return
end

#########################################################################
# Hard-coded constant values, copied from numpy/ndarraytypes.h ...
# the values of these seem to have been stable for some time, and
# the NumPy developers seem to have some awareness of binary compatibility

# NumPy Types:

const NPY_BOOL = Int32(0)
const NPY_BYTE = Int32(1)
const NPY_UBYTE = Int32(2)
const NPY_SHORT = Int32(3)
const NPY_USHORT = Int32(4)
const NPY_INT = Int32(5)
const NPY_UINT = Int32(6)
const NPY_LONG = Int32(7)
const NPY_ULONG = Int32(8)
const NPY_LONGLONG = Int32(9)
const NPY_ULONGLONG = Int32(10)
const NPY_FLOAT = Int32(11)
const NPY_DOUBLE = Int32(12)
const NPY_LONGDOUBLE = Int32(13)
const NPY_CFLOAT = Int32(14)
const NPY_CDOUBLE = Int32(15)
const NPY_CLONGDOUBLE = Int32(16)
const NPY_OBJECT = Int32(17)
const NPY_STRING = Int32(18)
const NPY_UNICODE = Int32(19)
const NPY_VOID = Int32(20)
const NPY_HALF = Int32(23)

#########################################################################
# conversion from Julia types to NumPy types

npy_type(::Type{Bool}) = NPY_BOOL
npy_type(::Type{Int8}) = NPY_BYTE
npy_type(::Type{UInt8}) = NPY_UBYTE
npy_type(::Type{Int16}) = NPY_SHORT
npy_type(::Type{UInt16}) = NPY_USHORT
npy_type(::Type{Int32}) = NPY_INT
npy_type(::Type{UInt32}) = NPY_UINT
npy_type(::Type{Int64}) = NPY_LONGLONG
npy_type(::Type{UInt64}) = NPY_ULONGLONG
npy_type(::Type{Float16}) = NPY_HALF
npy_type(::Type{Float32}) = NPY_FLOAT
npy_type(::Type{Float64}) = NPY_DOUBLE
npy_type(::Type{ComplexF32}) = NPY_CFLOAT
npy_type(::Type{ComplexF64}) = NPY_CDOUBLE
npy_type(::Type{PyPtr}) = NPY_OBJECT

# flags:
const NPY_ARRAY_ALIGNED = Int32(0x0100)
const NPY_ARRAY_WRITEABLE = Int32(0x0400)

#########################################################################
# no-copy conversion of Julia arrays to NumPy arrays.

# Julia arrays are in column-major order, but in some cases it is useful
# to pass them to Python as row-major arrays simply by reversing the
# dimensions. For example, although NumPy works with both row-major and
# column-major data, some Python libraries like OpenCV seem to require
# row-major data (the default in NumPy). In such cases, use PyReverseDims(array)
function NpyArray(a::StridedArray{T}, revdims::Bool) where T<:PYARR_TYPES
    @npyinitialize
    size_a = revdims ? reverse(size(a)) : size(a)
    strides_a = revdims ? reverse(strides(a)) : strides(a)
    p = @pycheck ccall(npy_api[:PyArray_New], PyPtr,
          (PyPtr,Cint,Ptr{Int},Cint, Ptr{Int},Ptr{T}, Cint,Cint,PyPtr),
          npy_api[:PyArray_Type],
          ndims(a), Int[size_a...], npy_type(T),
          Int[strides_a...] * sizeof(eltype(a)), a, sizeof(eltype(a)),
          NPY_ARRAY_ALIGNED | NPY_ARRAY_WRITEABLE,
          C_NULL)
    return PyObject(p, a)
end

function PyObject(a::StridedArray{T}) where T<:PYARR_TYPES
    try
        return NpyArray(a, false)
    catch
        return array2py(a) # fallback to non-NumPy version
    end
end

function PyReverseDims(a::StridedArray{T,N}) where {T<:PYARR_TYPES,N}
    try
        return NpyArray(a, true)
    catch
        return array2py(permutedims(a, N:-1:1)) # fallback to non-NumPy version
    end
end
PyReverseDims(a::BitArray) = PyReverseDims(Array(a))

# fallback to physically transposing the array
PyReverseDims(a::AbstractArray{<:Any,N}) where {N} = PyObject(permutedims(a, N:-1:1))
PyReverseDims(a::AbstractMatrix) = PyObject(permutedims(a))

"""
    PyReverseDims(array)

Passes a Julia `array` to Python as a NumPy row-major array
(rather than Julia's native column-major order) with the
dimensions reversed (e.g. a 2×3×4 Julia array is passed as
a 4×3×2 NumPy row-major array).  This is useful for Python
libraries that expect row-major data.
"""
PyReverseDims(a::AbstractArray)

#########################################################################

# transposed arrays can be passed to NumPy without copying
PyObject(a::Union{LinearAlgebra.Adjoint{<:Real},LinearAlgebra.Transpose}) =
    PyReverseDims(a.parent)

PyObject(a::LinearAlgebra.Adjoint) = PyObject(Matrix(a)) # non-real arrays require a copy
