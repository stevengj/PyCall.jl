#########################################################################
# PyVector: no-copy wrapping of a Julia object around a Python sequence

"""
    PyVector(o::PyObject)

This returns a PyVector object, which is a wrapper around an arbitrary Python list or sequence object.

Alternatively, `PyVector` can be used as the return type for a `pycall` that returns a sequence object (including tuples).
"""
mutable struct PyVector{T} <: AbstractVector{T}
    o::PyObject
    function PyVector{T}(o::PyObject) where T
        if ispynull(o)
            throw(ArgumentError("cannot make PyVector from NULL PyObject"))
        end
        new{T}(o)
    end
end

PyVector(o::PyObject) = PyVector{PyAny}(o)
PyObject(a::PyVector) = a.o
convert(::Type{PyVector}, o::PyObject) = PyVector(o)
convert(::Type{PyVector{T}}, o::PyObject) where {T} = PyVector{T}(o)
unsafe_convert(::Type{PyPtr}, a::PyVector) = PyPtr(a.o)
PyVector(a::PyVector) = a
PyVector(a::AbstractVector{T}) where {T} = PyVector{T}(array2py(a))

# when a PyVector is copied it is converted into an ordinary Julia Vector
similar(a::PyVector, T, dims::Dims) = Array{T}(dims)
similar(a::PyVector{T}) where {T} = similar(a, pyany_toany(T), size(a))
similar(a::PyVector{T}, dims::Dims) where {T} = similar(a, pyany_toany(T), dims)
similar(a::PyVector{T}, dims::Int...) where {T} = similar(a, pyany_toany(T), dims)
eltype(::PyVector{T}) where {T} = pyany_toany(T)
eltype(::Type{PyVector{T}}) where {T} = pyany_toany(T)

size(a::PyVector) = (length(a.o),)

getindex(a::PyVector) = getindex(a, 1)
getindex(a::PyVector{T}, i::Integer) where {T} = convert(T, PyObject(@pycheckn ccall((@pysym :PySequence_GetItem), PyPtr, (PyPtr, Int), a, i-1)))

setindex!(a::PyVector, v) = setindex!(a, v, 1)
function setindex!(a::PyVector, v, i::Integer)
    @pycheckz ccall((@pysym :PySequence_SetItem), Cint, (PyPtr, Int, PyPtr), a, i-1, PyObject(v))
    v
end

summary(a::PyVector{T}) where {T} = string(Base.dims2string(size(a)), " ",
                                          string(pyany_toany(T)), " PyVector")

splice!(a::PyVector, i::Integer) = splice!(a.o, i)
function splice!(a::PyVector{T}, indices::AbstractVector{I}) where {T,I<:Integer}
    v = pyany_toany(T)[a[i] for i in indices]
    for i in sort(indices, rev=true)
        @pycheckz ccall((@pysym :PySequence_DelItem), Cint, (PyPtr, Int), a, i-1)
    end
    v
end
pop!(a::PyVector) = pop!(a.o)
popfirst!(a::PyVector) = popfirst!(a.o)
empty!(a::PyVector) = empty!(a.o)

# only works for List subtypes:
push!(a::PyVector, item) = push!(a.o, item)
insert!(a::PyVector, i::Integer, item) = insert!(a.o, i, item)
pushfirst!(a::PyVector, item) = pushfirst!(a.o, item)
prepend!(a::PyVector, items) = prepend!(a.o, items)
append!(a::PyVector{T}, items) where {T} = PyVector{T}(append!(a.o, items))

