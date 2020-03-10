# jlwrap notes

* All the structs should be immutable really, with better constructors (i.e. `PyType_Ready` should be called before the inner constructor finishes, after which the type is immutable)
* `jlwrap_type(::Type{T})` looks up `T` in a `IdDict{Type,PyObject}`, if it's there returns it, otherwise returns `jlwrap_new_type(T)`
* `jlwrap_new_type(::Type{T})` returns a (new) `PyObject` which is a `type` (or maybe some subtype of `type` specifically for julia types? call it `juliatype`?) representing the julia type `T`, it has one supertype (either its julia supertype, or `object` if `T` is `Any`) --- so the julia type system is embedded into the python one, with the root `Any` being a direct subtype of `object`.
* such a type object should have methods to interact with the julia type system, such as getting its supertypes, subtypes, parameters, or specializing parameters (note that each parameterization of a type is a new type in the python system)
* `jlwrap_object(x)` returns `jlwrap_new_object(x)`
* `jlwrap_new_object(x::T)` returns a (new) `PyObject` wrapping `x` whose type is `jlwrap_type(T)`
* `jlwrap(x)` returns `jlwrap_type` or `jlwrap_object` depending on whether `x` is a type or not
* have a test to determine if a python object is a wrap of some julia thing, namely it was created by `jlwrap_type` or `jlwrap_new_type`
* if the version of python supports abstract base classes (ABCs), then:
  * have an ABC for `jlwrap`, which `jlwrap_type(Any)` and `juliatype` are both subclassses of?
  * apply other ABCs to objects which support certain operations



We should have a type that represents the translation of semantics between julia and python. For example, it should have a `getattr` field, which is a namedtuple mapping symbols to functions, then we define something like:

```
jlwrap_getattr(o, a) = _jlwrap_getattr(unwrap(pytypeof(o)), unwrap(o), Symbol(string(a)))

_jlwrap_getattr(t, o, a) = haskey(t.getattr, a) ? t.getattr[a](o) : _jlwrap_getattr_dflt(o, a)

_jlwrap_getattr_dflt(o, a) = startswith(string(a), "__") ? (do the right python thing) : getproperty(o, a)
```