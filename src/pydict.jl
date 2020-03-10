#########################################################################
# PyDict: no-copy wrapping of a Julia object around a Python dictionary

# we check for "items" attr since PyMapping_Check doesn't do this (it only
# checks for __getitem__) and PyMapping_Check returns true for some
# scipy scalar array members, grrr.
function is_mapping_object(o::PyObject)
    pyisinstance(o, @pyglobalobj :PyDict_Type) ||
    (pyquery((@pyglobal :PyMapping_Check), o) &&
      ccall((@pysym :PyObject_HasAttrString), Cint, (PyPtr,Ptr{UInt8}), o, "items") == 1)
end

"""
    PyDict(o::PyObject)
    PyDict(d::Dict{K,V})

This returns a PyDict, which is a no-copy wrapper around a Python dictionary.

Alternatively, you can specify the return type of a `pycall` as PyDict.
"""
mutable struct PyDict{K,V,isdict} <: AbstractDict{K,V}
    o::PyObject
    # isdict = true for python dict, otherwise is a generic Mapping object

    function PyDict{K,V,isdict}(o::PyObject) where {K,V,isdict}
        if !isdict && !ispynull(o) && !is_mapping_object(o)
            throw(ArgumentError("only Dict and Mapping objects can be converted to PyDict"))
        end
        return new{K,V,isdict}(o)
    end
end

PyDict{K,V}(o::PyObject) where {K,V} = PyDict{K,V,pyisinstance(o, @pyglobalobj :PyDict_Type)}(o)
PyDict{K,V}() where {K,V} = PyDict{K,V,true}(PyObject(@pycheckn ccall((@pysym :PyDict_New), PyPtr, ())))

PyDict(o::PyObject) = PyDict{PyAny,PyAny}(o)
PyObject(d::PyDict) = d.o
PyDict() = PyDict{PyAny,PyAny}()
PyDict(d::AbstractDict{K,V}) where {K,V} = PyDict{K,V}(PyObject(d))
PyDict(d::AbstractDict{Any,Any}) = PyDict{PyAny,PyAny}(PyObject(d))
PyDict(d::AbstractDict{Any,V}) where {V} = PyDict{PyAny,V}(PyObject(d))
PyDict(d::AbstractDict{K,Any}) where {K} = PyDict{K,PyAny}(PyObject(d))
convert(::Type{PyDict}, o::PyObject) = PyDict(o)
convert(::Type{PyDict{K,V}}, o::PyObject) where {K,V} = PyDict{K,V}(o)
unsafe_convert(::Type{PyPtr}, d::PyDict) = PyPtr(d.o)

haskey(d::PyDict{K,V,true}, key) where {K,V} = 1 == ccall(@pysym(:PyDict_Contains), Cint, (PyPtr, PyPtr), d, PyObject(key))
keys(::Type{T}, d::PyDict{K,V,true}) where {T,K,V} = convert(Vector{T}, PyObject(@pycheckn ccall((@pysym :PyDict_Keys), PyPtr, (PyPtr,), d)))
values(::Type{T}, d::PyDict{K,V,true}) where {T,K,V} = convert(Vector{T}, PyObject(@pycheckn ccall((@pysym :PyDict_Values), PyPtr, (PyPtr,), d)))

keys(::Type{T}, d::PyDict{K,V,false}) where {T,K,V} = convert(Vector{T}, pycall(d.o["keys"], PyObject))
values(::Type{T}, d::PyDict{K,V,false}) where {T,K,V} = convert(Vector{T}, pycall(d.o["values"], PyObject))
haskey(d::PyDict{K,V,false}, key) where {K,V} = 1 == ccall(@pysym(:PyMapping_HasKey), Cint, (PyPtr, PyPtr), d, PyObject(key))

similar(d::PyDict{K,V}) where {K,V} = Dict{pyany_toany(K),pyany_toany(V)}()
eltype(::Type{PyDict{K,V}}) where {K,V} = Pair{pyany_toany(K),pyany_toany(V)}
Base.keytype(::PyDict{K,V}) where {K,V} = pyany_toany(K)
Base.valtype(::PyDict{K,V}) where {K,V} = pyany_toany(V)
Base.keytype(::Type{PyDict{K,V}}) where {K,V} = pyany_toany(K)
Base.valtype(::Type{PyDict{K,V}}) where {K,V} = pyany_toany(V)

function setindex!(d::PyDict, v, k)
    @pycheckz ccall((@pysym :PyObject_SetItem), Cint, (PyPtr, PyPtr, PyPtr),
                     d, PyObject(k), PyObject(v))
    v
end

get(d::PyDict{K,V}, k, default) where {K,V} = get(d.o, V, k, default)

function pop!(d::PyDict{K,V,true}, k) where {K,V}
    v = d[k]
    @pycheckz ccall(@pysym(:PyDict_DelItem), Cint, (PyPtr, PyPtr), d, PyObject(k))
    return v
end
function pop!(d::PyDict{K,V,false}, k) where {K,V}
    v = d[k]
    @pycheckz ccall(@pysym(:PyObject_DelItem), Cint, (PyPtr, PyPtr), d, PyObject(k))
    return v
end

function pop!(d::PyDict, k, default)
    try
        return pop!(d, k)
    catch
        return default
    end
end

function delete!(d::PyDict{K,V,true}, k) where {K,V}
    e = ccall(@pysym(:PyDict_DelItem), Cint, (PyPtr, PyPtr), d, PyObject(k))
    e == -1 && pyerr_clear() # delete! ignores errors in Julia
    return d
end
function delete!(d::PyDict{K,V,false}, k) where {K,V}
    e = ccall(@pysym(:PyObject_DelItem), Cint, (PyPtr, PyPtr), d, PyObject(k))
    e == -1 && pyerr_clear() # delete! ignores errors in Julia
    return d
end

function empty!(d::PyDict{K,V,true}) where {K,V}
    @pycheck ccall((@pysym :PyDict_Clear), Cvoid, (PyPtr,), d)
    return d
end
function empty!(d::PyDict{K,V,false}) where {K,V}
    # for generic Mapping items we must delete keys one by one
    for k in keys(d)
        delete!(d, k)
    end
    return d
end

length(d::PyDict{K,V,true}) where {K,V} = @pycheckz ccall(@pysym(:PyDict_Size), Int, (PyPtr,), d)
length(d::PyDict{K,V,false}) where {K,V} = @pycheckz ccall(@pysym(:PyObject_Size), Int, (PyPtr,), d)
isempty(d::PyDict) = length(d) == 0


struct PyDict_Iterator
    # arrays to pass key, value, and pos pointers to PyDict_Next
    ka::Ref{PyPtr}
    va::Ref{PyPtr}
    pa::Ref{Int}
    i::Int # current position in items list (0-based)
    len::Int # length of items list
end

function Base.iterate(d::PyDict{K,V,true}, itr=PyDict_Iterator(Ref{PyPtr}(), Ref{PyPtr}(), Ref(0), 0, length(d))) where {K,V}
    itr.i >= itr.len && return nothing
    if 0 == ccall((@pysym :PyDict_Next), Cint,
                    (PyPtr, Ref{Int}, Ref{PyPtr}, Ref{PyPtr}),
                    d, itr.pa, itr.ka, itr.va)
        error("unexpected end of PyDict_Next")
    end
    ko = pyincref(itr.ka[]) # PyDict_Next returns
    vo = pyincref(itr.va[]) #   borrowed ref, so incref
    (Pair(convert(K,ko), convert(V,vo)),
        PyDict_Iterator(itr.ka, itr.va, itr.pa, itr.i+1, itr.len))
end

# Iterator for generic mapping, using Python items iterator.
# Our approach is to wrap an iterator over d.o["items"]
# which necessitates including d.o["items"] in the state.
function _start(d::PyDict{K,V,false}) where {K,V}
    d_items = pycall(d.o."items", PyObject)
    (d_items, iterate(d_items))
end
function Base.iterate(d::PyDict{K,V,false}, itr=_start(d)) where {K,V}
    d_items, iter_result = itr
    iter_result === nothing && return nothing
    item, state = iter_result
    iter_result = iterate(d_items, state)
    (item[1] => item[2], (d_items, iter_result))
end

