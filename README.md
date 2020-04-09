# What is this sorcery?!

Stack2nix is a small script that takes a stackage snapshot metadata and produces a nix derivation from it.

# How do I use it?

Like this:
```
$ stack2nix.sh --cabal-hashes path/to/all-cabal-hashes --snapshots path/to/stackage-snapshots --lts lts-15.1 --output path/to/output/directory
```

# What else do I need?
Hard dependencies are `jq` for parsing json, `yq` for parsing yaml, and `cabal2nix` for obvious reasons. If you have `nixfmt` somewhere in your $PATH, it'll also be used to format generated nix expressions, but it's not a hard requirement.

On top of those tools, you need copies of [all-cabal-hashes](https://github.com/commercialhaskell/all-cabal-hashes) and [stackage-snapshots](https://github.com/commercialhaskell/stackage-snapshots) checked out somewhere.

# Anything else I need to know?

This is work in progress yet. Do not blame me if you use it for anything serious and all hell breaks loose.
