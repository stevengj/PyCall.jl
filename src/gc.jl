# Interactions of the Julia and Python garbage collection:
#
#    * When we wrap a Python object in a Julia object jo (e.g. a PyDict),
#      we keep an explicit PyObject reference inside jo, whose finalizer
#      decrefs the Python object when it is called.
#
#    * When we wrap a Julia object jo inside a Python object po
#      (e.g a numpy array), we add jo to the pycall_gc dictionary,
#      keyed by a weak reference to po.  The Python weak reference
#      allows us to register a callback function that is called
#      when po is deallocated, and this callback function removes
#      jo from pycall_gc so that Julia can garbage-collect it.

const pycall_gc = Dict{PyPtr,Any}()

function weakref_callback(callback::PyPtr, wo::PyPtr)
    delete!(pycall_gc, wo)
    ccall((@pysym :Py_DecRef), Cvoid, (PyPtr,), wo)
    return pyincref_(pynothing[])
end

const weakref_callback_obj = PyNULL() # weakref_callback Python method

# Python expects the PyMethodDef structure to be a constant, so
# we put it in a global to prevent gc.
const weakref_callback_meth = Ref{CPyMethodDef}()

# "embed" a reference to jo in po, using the weak-reference mechanism
function pyembed(po::PyObject, jo::Any)
    # If there's a need to support immutable embedding,
    # the API needs to be changed to return the pointer.
    isimmutable(jo) && throw(ArgumentError("pyembed: immutable argument not allowed"))
    if ispynull(weakref_callback_obj)
        cf = @cfunction(weakref_callback, PyPtr, (PyPtr,PyPtr))
        weakref_callback_meth[] = PyMethodDef("weakref_callback", cf, METH_O)
        copy!(weakref_callback_obj,
              PyObject(@pycheckn ccall((@pysym :PyCFunction_NewEx), PyPtr,
                                       (Ref{CPyMethodDef}, Ptr{Cvoid}, Ptr{Cvoid}),
                                       weakref_callback_meth, C_NULL, C_NULL)))
    end
    wo = @pycheckn ccall((@pysym :PyWeakref_NewRef), PyPtr, (PyPtr,PyPtr),
                         po, weakref_callback_obj)
    pycall_gc[wo] = jo
    return po
end
