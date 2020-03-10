# Support Python iterators in Julia and vice versa

#########################################################################
# Iterating over Python objects in Julia

Base.IteratorSize(::Type{PyObject}) = Base.SizeUnknown()
function _start(po::PyObject)
    disable_sigint() do
        o = PyObject(@pycheckn ccall((@pysym :PyObject_GetIter), PyPtr, (PyPtr,), po))
        nxt = PyObject(@pycheck ccall((@pysym :PyIter_Next), PyPtr, (PyPtr,), o))

        return (nxt,o)
    end
end

"""
    PyIterator{T}(pyobject)

Wrap `pyobject::PyObject` into an iterator, that produces items of type `T`. To be more precise `convert(T, item)` is applied in each iteration. This can be useful to avoid automatic conversion of items into corresponding julia types.
```jldoctest
julia> using PyCall

julia> l = PyObject([PyObject(1), PyObject(2)])
PyObject [1, 2]

julia> piter = PyCall.PyIterator{PyAny}(l)
PyCall.PyIterator{PyAny,Base.HasLength()}(PyObject [1, 2])

julia> collect(piter)
2-element Array{Any,1}:
    1
    2

julia> piter = PyCall.PyIterator(l)
PyCall.PyIterator{PyObject,Base.HasLength()}(PyObject [1, 2])

julia> collect(piter)
2-element Array{PyObject,1}:
    PyObject 1
    PyObject 2
```
"""
struct PyIterator{T,S}
    o::PyObject
end

function _compute_IteratorSize(o::PyObject)
    S = try
        length(o)
        Base.HasLength
    catch err
        if !(err isa PyError && pyisinstance(err.val, @pyglobalobjptr :PyExc_TypeError))
            rethrow()
        end
        Base.SizeUnknown
    end
end
function PyIterator(o::PyObject)
    PyIterator{PyObject}(o)
end
function (::Type{PyIterator{T}})(o::PyObject) where {T}
    S = _compute_IteratorSize(o)
    PyIterator{T,S}(o)
end

Base.eltype(::Type{<:PyIterator{T}}) where T = T
Base.eltype(::Type{<:PyIterator{PyAny}}) = Any
Base.length(piter::PyIterator) = length(piter.o)

Base.IteratorSize(::Type{<: PyIterator{T,S}}) where {T,S} = S()

_start(piter::PyIterator) = _start(piter.o)

function Base.iterate(piter::PyIterator{T}, s=_start(piter)) where {T}
    ispynull(s[1]) && return nothing
    disable_sigint() do
        nxt = PyObject(@pycheck ccall((@pysym :PyIter_Next), PyPtr, (PyPtr,), s[2]))
        return (convert(T,s[1]), (nxt, s[2]))
    end
end
function Base.iterate(po::PyObject, s=_start(po))
    # avoid the constructor that calls length
    # since that might be an expensive operation
    # even if length is cheap, this adds 10% performance
    piter = PyIterator{PyAny, Base.SizeUnknown}(po)
    iterate(piter, s)
end

# issue #216
function Base.collect(::Type{T}, o::PyObject) where T
    a = T[]
    for x in o
        push!(a, x)
    end
    return a
end
Base.collect(o::PyObject) = collect(Any, o)

#########################################################################
# Broadcasting: if the object is iterable, return collect(o), and otherwise
#               return o.
function Base.Broadcast.broadcastable(o::PyObject)
    iter = ccall((@pysym :PyObject_GetIter), PyPtr, (PyPtr,), o)
    if iter == C_NULL
        pyerr_clear()
        return Ref(o)
    else
        ccall(@pysym(:Py_DecRef), Cvoid, (PyPtr,), iter)
        return collect(o)
    end
end
