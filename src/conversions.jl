# Conversions between Julia and Python types for the PyCall module.

# Conversion from julia to python defers to CPyObject_From, which is partly defined in libpython/extensions.jl, and partly defined below
PyObject(x) = PyObject(CPyObject_From(x))

CPyObject_From(x) =
    CPyJlWrap_From(x)
CPyObject_From(x::PyObject) =
    CPyObject_From(PyPtr(x))
CPyObject_From(t::Ref{CPyTypeObject}) =
    CPyObject_From(Base.unsafe_convert(PyPtr, t))

#########################################################################
# for automatic conversions, I pass Vector{PyAny}, NTuple{N, PyAny}, etc.,
# but since PyAny is an abstract type I need to convert this to Any
# before actually creating the Julia object

# I want to use a union, but this seems to confuse Julia's method
# dispatch for the convert function in some circumstances
# const PyAny = Union{PyObject, Int, Bool, Float64, ComplexF64, AbstractString, Function, Dict, Tuple, Array}
abstract type PyAny end

function pyany_toany(T::Type)
    T === Vararg{PyAny} ? Vararg{Any} : T
end
pyany_toany(::Type{PyAny}) = Any
pyany_toany(t::Type{T}) where {T<:Tuple} = Tuple{map(pyany_toany, t.types)...}

# PyAny acts like Any for conversions, except for converting PyObject (below)
convert(::Type{PyAny}, x) = x

function convert(::Type{PyAny}, o::PyObject)
    if ispynull(o)
        return o
    end
    # automatic conversion back disabled for now
    return o
    # try
    #     T = pytype_query(o)
    #     if T == PyObject && is_pyjlwrap(o)
    #         return unsafe_pyjlwrap_load_value(o)
    #     end
    #     convert(T, o)
    # catch
    #     pyerr_clear() # just in case
    #     o
    # end
end

# #########################################################################
# # Conversions of simple types (numbers and nothing)

# # conversions from Julia types to PyObject:

# @static if pyversion < v"3"
#     PyObject(i::Unsigned) = PyObject(@pycheckn ccall(@pysym(:PyInt_FromSize_t),
#                                                     PyPtr, (UInt,), i))
#     PyObject(i::Integer) = PyObject(@pycheckn ccall(@pysym(:PyInt_FromSsize_t),
#                                                     PyPtr, (Int,), i))
# else
#     PyObject(i::Unsigned) = PyObject(@pycheckn ccall(@pysym(:PyLong_FromUnsignedLongLong),
#                                                     PyPtr, (Culonglong,), i))
#     PyObject(i::Integer) = PyObject(@pycheckn ccall(@pysym(:PyLong_FromLongLong),
#                                                     PyPtr, (Clonglong,), i))
# end

# PyObject(b::Bool) = PyObject(@pycheckn ccall((@pysym :PyBool_FromLong),
#                                              PyPtr, (Clong,), b))

# PyObject(r::Real) = PyObject(@pycheckn ccall((@pysym :PyFloat_FromDouble),
#                                              PyPtr, (Cdouble,), r))

# PyObject(c::Complex) = PyObject(@pycheckn ccall((@pysym :PyComplex_FromDoubles),
#                                                 PyPtr, (Cdouble,Cdouble),
#                                                 real(c), imag(c)))

# PyObject(n::Nothing) = pyerr_check("PyObject(nothing)", pyincref(pynothing[]))

# # conversions to Julia types from PyObject

# @static if pyversion < v"3"
#     convert(::Type{T}, po::PyObject) where {T<:Integer} =
#         T(@pycheck ccall(@pysym(:PyInt_AsSsize_t), Int, (PyPtr,), po))
# elseif pyversion < v"3.2"
#     convert(::Type{T}, po::PyObject) where {T<:Integer} =
#         T(@pycheck ccall(@pysym(:PyLong_AsLongLong), Clonglong, (PyPtr,), po))
# else
#     function convert(::Type{T}, po::PyObject) where {T<:Integer}
#         overflow = Ref{Cint}()
#         val = T(@pycheck ccall(@pysym(:PyLong_AsLongLongAndOverflow), Clonglong, (PyPtr, Ref{Cint}), po, overflow))
#         iszero(overflow[]) || throw(InexactError(:convert, T, po))
#         return val
#     end
#     function convert(::Type{Integer}, po::PyObject)
#         overflow = Ref{Cint}()
#         val = @pycheck ccall(@pysym(:PyLong_AsLongLongAndOverflow), Clonglong, (PyPtr, Ref{Cint}), po, overflow)
#         iszero(overflow[]) || return convert(BigInt, po)
#         return val
#     end
# end

# convert(::Type{Bool}, po::PyObject) =
#     0 != @pycheck ccall(@pysym(:PyObject_IsTrue), Cint, (PyPtr,), po)

# convert(::Type{T}, po::PyObject) where {T<:Real} =
#     T(@pycheck ccall(@pysym(:PyFloat_AsDouble), Cdouble, (PyPtr,), po))

# convert(::Type{T}, po::PyObject) where T<:Complex =
#     T(@pycheck ccall(@pysym(:PyComplex_AsCComplex), Complex{Cdouble}, (PyPtr,), po))

# convert(::Type{Nothing}, po::PyObject) = nothing

# function Base.float(o::PyObject)
#     a = PyAny(o)
#     if a isa PyObject
#         hasproperty(o, :__float__) && return o.__float__()
#         throw(ArgumentError("don't know how convert $o to a Julia floating-point value"))
#     end
#     return float(a)
# end

# #########################################################################
# # String conversions (both bytes arrays and unicode strings)

# function PyObject(s::AbstractString)
#     sb = String(s)
#     if pyunicode_literals || !isascii(sb)
#         PyObject(@pycheckn ccall(@pysym(PyUnicode_DecodeUTF8),
#                                  PyPtr, (Ptr{UInt8}, Int, Ptr{UInt8}),
#                                  sb, sizeof(sb), C_NULL))
#     else
#         pybytes(sb)
#     end
# end

# const _ps_ptr= Ptr{UInt8}[C_NULL]
# const _ps_len = Int[0]
# function convert(::Type{T}, po::PyObject) where T<:AbstractString
#     if pyisinstance(po, @pyglobalobj :PyUnicode_Type)
#         convert(T, PyObject(@pycheckn ccall(@pysym(PyUnicode_AsUTF8String),
#                                              PyPtr, (PyPtr,), po)))
#     else
#         @pycheckz ccall(@pysym(PyString_AsStringAndSize),
#                         Cint, (PyPtr, Ptr{Ptr{UInt8}}, Ptr{Int}),
#                         po, _ps_ptr, _ps_len)
#         convert(T, unsafe_string(_ps_ptr[1], _ps_len[1]))
#     end
# end

# # TODO: should symbols be converted to a subclass of Python strings/bytes,
# #       so that PyAny conversion can convert it back to a Julia symbol?
# PyObject(s::Symbol) = PyObject(string(s))
# convert(::Type{Symbol}, po::PyObject) = Symbol(convert(AbstractString, po))

# #########################################################################
# # ByteArray conversions

# function PyObject(a::DenseVector{UInt8})
#   if stride(a,1) != 1
#     try
#         return NpyArray(a, true)
#     catch
#         return array2py(a) # fallback to non-NumPy version
#     end
#   end
#   PyObject(@pycheckn ccall((@pysym :PyByteArray_FromStringAndSize),
#                            PyPtr, (Ptr{UInt8}, Int), a, length(a)))
# end


# ispybytearray(po::PyObject) =
#   pyisinstance(po, @pyglobalobj :PyByteArray_Type)

# function convert(::Type{Vector{UInt8}}, po::PyObject)
#     b = PyBuffer(po)
#     iscontiguous(b) || error("a contiguous buffer is required")
#     return copy(unsafe_wrap(Array, Ptr{UInt8}(pointer(b)), sizeof(b)))
# end

# # TODO: support zero-copy PyByteArray <: AbstractVector{UInt8} object

# #########################################################################
# # Pointer conversions, using ctypes or PyCapsule

# PyObject(p::Ptr) = pycall(c_void_p_Type, PyObject, UInt(p))

# function convert(::Type{Ptr{Cvoid}}, po::PyObject)
#     if pyisinstance(po, c_void_p_Type)
#         v = po."value"
#         # ctypes stores the NULL pointer specially, grrr
#         pynothing_query(v) == Nothing ? C_NULL :
#           convert(Ptr{Cvoid}, convert(UInt, po."value"))
#     elseif pyisinstance(po, @pyglobalobj(:PyCapsule_Type))
#         @pycheck ccall((@pysym :PyCapsule_GetPointer),
#                        Ptr{Cvoid}, (PyPtr,Ptr{UInt8}),
#                        po, ccall((@pysym :PyCapsule_GetName),
#                                  Ptr{UInt8}, (PyPtr,), po))
#     else
#         convert(Ptr{Cvoid}, convert(UInt, po))
#     end
# end

# pyptr_query(po::PyObject) = pyisinstance(po, c_void_p_Type) || pyisinstance(po, @pyglobalobj(:PyCapsule_Type)) ? Ptr{Cvoid} : Union{}

# #########################################################################
# # Function conversion (see callback.jl for conversion the other way)
# # (rarely needed given call overloading in Julia 0.4)

# convert(::Type{Function}, po::PyObject) =
#     function fn(args...; kwargs...)
#         pycall(po, PyAny, args...; kwargs...)
#     end

# #########################################################################
# # Tuple conversion.  Julia Pairs are treated as Python tuples.

# function PyObject(t::Union{Tuple,Pair})
#     len = lastindex(t) # lastindex, not length, because of julia#14924
#     o = PyObject(@pycheckn ccall((@pysym :PyTuple_New), PyPtr, (Int,), len))
#     for i = 1:len
#         oi = PyObject(t[i])
#         @pycheckz ccall((@pysym :PyTuple_SetItem), Cint, (PyPtr,Int,PyPtr),
#                          o, i-1, oi)
#         pyincref(oi) # PyTuple_SetItem steals the reference
#     end
#     return o
# end

# # somewhat annoying to get the length and types in a tuple type
# # ... would be better not to have to use undocumented internals!
# istuplen(T,isva,n) = isva ? n ≥ length(T.parameters)-1 : n == length(T.parameters)
# function tuptype(T::DataType,isva,i)
#     if isva && i ≥ length(T.parameters)
#         return Base.unwrapva(T.parameters[end])
#     else
#         return T.parameters[i]
#     end
# end
# tuptype(T::UnionAll,isva,i) = tuptype(T.body,isva,i)
# isvatuple(T::UnionAll) = isvatuple(T.body)
# isvatuple(T::DataType) = !isempty(T.parameters) && Base.isvarargtype(T.parameters[end])

# function convert(tt::Type{T}, o::PyObject) where T<:Tuple
#     isva = isvatuple(T)
#     len = @pycheckz ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#     if !istuplen(tt, isva, len)
#         throw(BoundsError())
#     end
#     ntuple((i ->
#             convert(tuptype(T, isva, i),
#                     PyObject(ccall((@pysym :PySequence_GetItem), PyPtr,
#                                    (PyPtr, Int), o, i-1)))),
#            len)
# end

# function convert(::Type{Pair{K,V}}, o::PyObject) where {K,V}
#     k, v = convert(Tuple{K,V}, o)
#     return Pair(k, v)
# end

# #########################################################################
# # Lists and 1d arrays.

# if VERSION < v"1.1.0-DEV.392" # #29440
#     cirange(I,J) = CartesianIndices(map((i,j) -> i:j, Tuple(I), Tuple(J)))
# else
#     cirange(I,J) = I:J
# end

# # recursive conversion of A to a list of list of lists... starting
# # with dimension dim and Cartesian index i in A.
# function array2py(A::AbstractArray{<:Any, N}, dim::Integer, i::CartesianIndex{N}) where {N}
#     if dim > N # base case
#         return PyObject(A[i])
#     else # recursively store multidimensional array as list of lists
#         ilast = CartesianIndex(ntuple(j -> j == dim ? lastindex(A, dim) : i[j], Val{N}()))
#         o = PyObject(@pycheckn ccall((@pysym :PyList_New), PyPtr, (Int,), size(A, dim)))
#         for icur in cirange(i,ilast)
#             oi = array2py(A, dim+1, icur)
#             @pycheckz ccall((@pysym :PyList_SetItem), Cint, (PyPtr,Int,PyPtr),
#                              o, icur[dim]-i[dim], oi)
#             pyincref(oi) # PyList_SetItem steals the reference
#         end
#         return o
#     end
# end

# array2py(A::AbstractArray) = array2py(A, 1, first(CartesianIndices(A)))

# #=PyObject(A::AbstractArray) =
#    ndims(A) <= 1 || hasmethod(stride, Tuple{typeof(A),Int}) ? array2py(A) :
#    pyjlwrap_new(A)=#

# function py2array(T, A::Array{TA,N}, o::PyObject,
#                   dim::Integer, i::Integer) where {TA,N}
#     if dim > N
#         A[i] = convert(T, o)
#         return A
#     elseif dim == N
#         len = @pycheckz ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#         if len != size(A, dim)
#             error("dimension mismatch in py2array")
#         end
#         s = stride(A, dim)
#         for j = 0:len-1
#             A[i+j*s] = convert(T, PyObject(ccall((@pysym :PySequence_GetItem),
#                                                  PyPtr, (PyPtr, Int), o, j)))
#         end
#         return A
#     else # dim < N: recursively extract list of lists into A
#         len = @pycheckz ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#         if len != size(A, dim)
#             error("dimension mismatch in py2array")
#         end
#         s = stride(A, dim)
#         for j = 0:len-1
#             py2array(T, A, PyObject(ccall((@pysym :PySequence_GetItem),
#                                        PyPtr, (PyPtr, Int), o, j)),
#                      dim+1, i+j*s)
#         end
#         return A
#     end
# end

# # figure out if we can treat o as a multidimensional array, and return
# # the dimensions
# function pyarray_dims(o::PyObject, forcelist=true)
#     if !(forcelist || pyisinstance(o, @pyglobalobj :PyList_Type))
#         return () # too many non-List types can pretend to be sequences
#     end
#     len = ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#     len < 0 && error("not a PySequence object")
#     if len == 0
#         return (0,)
#     end
#     dims0 = pyarray_dims(PyObject(ccall((@pysym :PySequence_GetItem),
#                                         PyPtr, (PyPtr, Int), o, 0)),
#                          false)
#     if isempty(dims0) # not a nested sequence
#         return (len,)
#     end
#     for j = 1:len-1
#         dims = pyarray_dims(PyObject(ccall((@pysym :PySequence_GetItem),
#                                            PyPtr, (PyPtr, Int), o, j)),
#                             false)
#         if dims != dims0
#             # elements don't have equal lengths, cannot
#             # treat as multidimensional array
#             return (len,)
#         end
#     end
#     return tuple(len, dims0...)
# end

# function py2array(T, o::PyObject)
#     b = PyBuffer()
#     if isbuftype!(o, b)
#         dims = size(b)
#     else
#         dims = pyarray_dims(o)
#     end
#     pydecref(b) # safe for immediate release
#     A = Array{pyany_toany(T)}(undef, dims)
#     py2array(T, A, o, 1, 1) # fixme: faster conversion for supported buffer types?
# end

# function py2vector(T, o::PyObject)
#     len = ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#     if len < 0 || # not a sequence
#        len+1 < 0  # object pretending to be a sequence of infinite length
#         pyerr_clear()
#         throw(ArgumentError("expected Python sequence"))
#     end
#     py2array(T, Array{pyany_toany(T)}(undef, len), o, 1, 1)
# end
# convert(::Type{Vector{T}}, o::PyObject) where T = py2vector(T, o)

# convert(::Type{Array}, o::PyObject) = map(identity, py2array(PyAny, o))
# convert(::Type{Array{T}}, o::PyObject) where {T} = py2array(T, o)

# PyObject(a::BitArray) = PyObject(Array(a))

# #########################################################################
# # Dictionary conversions (copies)

# function PyObject(d::AbstractDict)
#     o = PyObject(@pycheckn ccall((@pysym :PyDict_New), PyPtr, ()))
#     for k in keys(d)
#         @pycheckz ccall((@pysym :PyDict_SetItem), Cint, (PyPtr,PyPtr,PyPtr),
#                          o, PyObject(k), PyObject(d[k]))
#     end
#     return o
# end

# function convert(::Type{Dict{K,V}}, o::PyObject) where {K,V}
#     copy(PyDict{K,V}(o))
# end

# #########################################################################
# # AbstractRange: integer ranges are converted to xrange,
# #                while other ranges (<: AbstractVector) are converted to lists

# xrange(start, stop, step) = pycall(pyxrange[], PyObject,
#                                    start, stop, step)

# function PyObject(r::AbstractRange{T}) where T<:Integer
#     s = step(r)
#     f = first(r)
#     l = last(r) + s
#     if max(f,l) > typemax(Clong) || min(f,l) < typemin(Clong)
#         # in Python 2.x, xrange is limited to Clong
#         PyObject(T[r...])
#     else
#         xrange(f, l, s)
#     end
# end

# function convert(::Type{T}, o::PyObject) where T<:AbstractRange
#     v = PyVector(o)
#     len = length(v)
#     if len == 0
#         return 1:0 # no way to get more info from an xrange
#     elseif len == 1
#         start = v[1]
#         return start:start
#     else
#         start = v[1]
#         stop = v[len]
#         step = v[2] - start
#         return step == 1 ? (start:stop) : (start:step:stop)
#     end
# end

# #########################################################################
# # BigFloat and Complex{BigFloat}: convert to/from Python mpmath types

# # load mpmath module & initialize.  Currently, this is done
# # the first time a BigFloat is converted to Python.  Alternatively,
# # we could do it when PyCall is initialized (if mpmath is available),
# # at the cost of slowing down initialization in the common case where
# # BigFloat conversion is not needed.
# const mpprec = [0]
# const mpmath = PyNULL()
# const mpf = PyNULL()
# const mpc = PyNULL()
# function mpmath_init()
#     if ispynull(mpmath)
#         copy!(mpmath, pyimport("mpmath"))
#         copy!(mpf, mpmath."mpf")
#         copy!(mpc, mpmath."mpc")
#     end
#     curprec = precision(BigFloat)
#     if mpprec[1] != curprec
#         mpprec[1] = curprec
#         mpmath."mp"."prec" = mpprec[1]
#     end
# end

# # TODO: When mpmath uses MPFR internally, can we avoid the string conversions?
# # Using strings will work regardless of the mpmath backend, but is annoying
# # both from a performance perspective and because it is a lossy conversion
# # (since strings use a decimal representation, while MPFR is binary).

# function PyObject(x::BigFloat)
#     mpmath_init()
#     pycall(mpf, PyObject, string(x))
# end

# function PyObject(x::Complex{BigFloat})
#     mpmath_init()
#     pycall(mpc, PyObject, string(real(x)), string(imag(x)))
# end

# convert(::Type{BigFloat}, o::PyObject) = parse(BigFloat, pystr(o))

# function convert(::Type{Complex{BigFloat}}, o::PyObject)
#     try
#         Complex{BigFloat}(convert(BigFloat, o."real"),
#                           convert(BigFloat, o."imag"))
#     catch
#         convert(Complex{BigFloat}, convert(Complex{Float64}, o))
#     end
# end

# pymp_query(o::PyObject) = pyisinstance(o, mpf) ? BigFloat : pyisinstance(o, mpc) ? Complex{BigFloat} : Union{}

# #########################################################################
# # (Int64), Int128 and BigInt conversion to Python "long" integers

# const LongInt = @static (Sys.WORD_SIZE==32) ? Union{Int64,UInt64,Int128,UInt128,BigInt} : Union{Int128,UInt128,BigInt}

# function PyObject(i::LongInt)
#     PyObject(@pycheckn ccall((@pysym :PyLong_FromString), PyPtr,
#                              (Ptr{UInt8}, Ptr{Cvoid}, Cint),
#                              String(string(i)), C_NULL, 10))
# end

# convert(::Type{BigInt}, o::PyObject) = parse(BigInt, pystr(o))

#########################################################################
# Dates (Calendar time)

#init_datetime() = nothing
#pydate_query(o) = Union{}

# #########################################################################
# # Inferring Julia types at runtime from Python objects:
# #
# # [Note that we sometimes use the PyFoo_Check API and sometimes we use
# #  PyObject_IsInstance(o, PyFoo_Type), since sometimes the former API
# #  is a macro (hence inaccessible in Julia).]

# # A type-query function f(o::PyObject) returns the Julia type
# # for use with the convert function, or Union{} if there isn't one.

# @static if pyversion < v"3"
#     pyint_query(o::PyObject) = pyisinstance(o, @pyglobalobj :PyInt_Type) ?
#         (pyisinstance(o, @pyglobalobj :PyBool_Type) ? Bool : Int) :
#         pyisinstance(o, @pyglobalobj :PyLong_Type) ? BigInt :
#         pyisinstance(o, npy_integer) ? Int : Union{}
# else
#     pyint_query(o::PyObject) = pyisinstance(o, @pyglobalobj :PyLong_Type) ?
#         (pyisinstance(o, @pyglobalobj :PyBool_Type) ? Bool : Integer) :
#         pyisinstance(o, npy_integer) ? Integer : Union{}
# end

# pyfloat_query(o::PyObject) = pyisinstance(o, @pyglobalobj :PyFloat_Type) ||  pyisinstance(o, npy_floating) ? Float64 : Union{}

# pycomplex_query(o::PyObject) =
#     pyisinstance(o, @pyglobalobj :PyComplex_Type) ||  pyisinstance(o, npy_complexfloating) ? ComplexF64 : Union{}

# pystring_query(o::PyObject) = pyisinstance(o, @pyglobalobj PyString_Type) ? AbstractString : pyisinstance(o, @pyglobalobj :PyUnicode_Type) ? String : Union{}

# # Given call overloading, all PyObjects are callable already, so
# # we never automatically convert to Function.
# pyfunction_query(o::PyObject) = Union{}

# pynothing_query(o::PyObject) = o ≛ pynothing[] ? Nothing : Union{}

# # We refrain from converting all objects that support the mapping protocol (PyMapping_Check)
# # to avoid converting types like Pandas `DataFrame` that are only lossily
# # representable as a Julia dictionary (issue #376).
# pydict_query(o::PyObject) = pyisinstance(o, @pyglobalobj :PyDict_Type) ? Dict{PyAny,PyAny} : Union{}

# typetuple(Ts) = Tuple{Ts...}

# function pysequence_query(o::PyObject)
#     # pyquery(:PySequence_Check, o) always succeeds according to the docs,
#     # but it seems we need to be careful; I've noticed that things like
#     # scipy define "fake" sequence types with intmax lengths and other
#     # problems
#     if pyisinstance(o, @pyglobalobj :PyTuple_Type)
#         len = @pycheckz ccall((@pysym :PySequence_Size), Int, (PyPtr,), o)
#         return typetuple(pytype_query(PyObject(ccall((@pysym :PySequence_GetItem), PyPtr, (PyPtr,Int), o,i-1)), PyAny) for i = 1:len)
#     elseif pyisinstance(o, pyxrange[])
#         return AbstractRange
#     # elseif ispybytearray(o)
#     #     return Vector{UInt8}
#     # elseif !isbuftype(o)
#     #     # only handle PyList for now
#     #     return pyisinstance(o, @pyglobalobj :PyList_Type) ? Array : Union{}
#     # else
#     #     T, native_byteorder = array_format(o)
#     #     if T == PyPtr
#     #         T = PyObject
#     #     end
#     #     return Array{T}
#     end
# end

# macro return_not_None(ex)
#     quote
#         T = $(esc(ex))
#         if T != Union{}
#             return T
#         end
#     end
# end

const pytype_queries = Tuple{PyObject,Type}[]
# """
#     pytype_mapping(pytype, jltype)

# Given a Python type object `pytype`, tell PyCall to convert it to
# `jltype` in `PyAny(object)` conversions.
# """
# function pytype_mapping(py::PyObject, jl::Type)
#     for (i,(p,j)) in enumerate(pytype_queries)
#         if p == py
#             pytype_queries[i] = (py,jl)
#             return pytype_queries
#         end
#     end
#     push!(pytype_queries, (py,jl))
# end
# """
#     pytype_query(o::PyObject, default=PyObject)

# Given a Python object `o`, return the corresponding
# native Julia type (defaulting to `default`) that we convert
# `o` to in `PyAny(o)` conversions.
# """
# function pytype_query(o::PyObject, default::TypeTuple=PyObject)
#     # TODO: Use some kind of hashtable (e.g. based on PyObject_Type(o)).
#     #       (A bit tricky to correctly handle Tuple and other containers.)
#     @return_not_None pyint_query(o)
#     pyisinstance(o, npy_bool) && return Bool
#     @return_not_None pyfloat_query(o)
#     @return_not_None pycomplex_query(o)
#     @return_not_None pystring_query(o)
#     # @return_not_None pyfunction_query(o)
#     @return_not_None pydate_query(o)
#     # @return_not_None pydict_query(o)
#     # @return_not_None pyptr_query(o)
#     @return_not_None pysequence_query(o)
#     @return_not_None pynothing_query(o)
#     @return_not_None pymp_query(o)
#     for (py,jl) in pytype_queries
#         if pyisinstance(o, py)
#             return jl
#         end
#     end
#     return default
# end

# convert(U::Union, o::PyObject) =
#     try
#         convert(U.a, o)
#     catch
#         try
#             convert(U.b, o)
#         catch
#             throw(MethodError(convert, (U,o)))
#         end
#     end
