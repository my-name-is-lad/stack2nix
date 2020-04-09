#!/usr/bin/env bash

CABAL_HASHES_DIR=
SNAPSHOTS_DIR=
LTS=
OUTPUT_DIR=
FMT=

pkgName() {
    echo "${1%-*}"
}

pkgVersion() {
    echo "${1##*-}"
}

callCabal2Nix() {
    local pkg=$1
    local flags=$2
    # XXX: Add flags support here

    local name=$(pkgName "$pkg")
    local ver=$(pkgVersion "$pkg")

    local sha=$(extractShaSum $name $ver)
    local output=$(cabal2nix --sha256 "$sha" "$CABAL_HASHES_DIR/$name/$ver/$name.cabal")

    echo "$output"
}

extractShaSum() {
    local name=$1
    local ver=$2

    local output=$(cat "$CABAL_HASHES_DIR/$name/$ver/$name.json" | jq '.["package-hashes"] | .["SHA256"]' | tr -d '"')

    echo "$output"
}

wrapDerivation() {
    local name="$1"
    local derivation="$2"

    echo "\"$name\" = callPackage ($derivation) {};"
}

readBuildPlan() {
    local plan=$1
    local path=$(tr '.-' '/' <<< "$plan")

    local pkgs=$(cat "$SNAPSHOTS_DIR/$path.yaml" | yq '.packages[] | .hackage | split("@") | .[0]' | tr -d '"')
    echo "$pkgs"
}

getCompiler() {
    local plan="$1"
    local path=$(tr '.-' '/' <<< "$plan")

    local compiler=$(cat "$SNAPSHOTS_DIR/$path.yaml" | yq '.resolver.compiler' | tr -d '".-')

    echo "$compiler"
}

makeDefaultNix() {
    local compiler="$1"
    local body=$(cat <<-EOT
{ callPackage, buildPackages, pkgs, stdenv, lib
, overrides ? (self: super: {})
, packageSetConfig ? (self: super: {})
}:

let
  inherit (lib) extends makeExtensible;
  haskellLib = pkgs.haskell.lib;
  inherit (haskellLib) makePackageSet;

  haskellPackages = pkgs.callPackage makePackageSet {
                      ghc = buildPackages.haskell.compiler.${compiler};
                      buildHaskellPackages = buildPackages.haskell.packages.${compiler};
                      package-set = import ./packages.nix;
                      inherit stdenv haskellLib extensible-self;
                    };

  compilerConfig = import  ./configuration-packages.nix { inherit pkgs haskellLib; };

  configurationCommon = if builtins.pathExists ./configuration-common.nix then import ./configuration-common.nix { inherit pkgs haskellLib; } else self: super: {};
  configurationNix = import (pkgs.path + "/pkgs/development/haskell-modules/configuration-nix.nix") { inherit pkgs haskellLib; };

  extensible-self = makeExtensible (extends overrides (extends configurationCommon (extends packageSetConfig (extends compilerConfig (extends configurationNix haskellPackages)))));

in extensible-self

EOT
    )
    echo "$body"
}

makePackagesNix() {
    local pkgs="$1"

    body="{ pkgs, stdenv, callPackage }:\
    \
    self: {\
    "

    for pkg in $pkgs; do
        #echo $pkg
        d=$(callCabal2Nix "$pkg")
        body="$body $(wrapDerivation $(pkgName $pkg) "$d")"
    done

    body="$body\
    }\
    "
    echo "$body"
}

makeConfigurationPackages() {
    local body=$(cat <<-EOT
{ pkgs, haskellLib }:

with haskellLib; self: super: {
# This is a stub for now
}
EOT
    )

    echo "$body"
}

checkOptions() {
    if [ "$CABAL_HASHES_DIR" = "" ]; then
        echo "all-cabal-hashes directory is not specified."
        echo "You can download a copy of all-cabal-hashes at https://github.com/commercialhaskell/all-cabal-hashes/tree/hackage."
        exit 1
    fi

    if [ "$SNAPSHOTS_DIR" = "" ]; then
        echo "Stackage snapshots directory is not specified."
        echo "You can download a copy at https://github.com/commercialhaskell/stackage-snapshots."
        exit 1
    fi

    if [ "$LTS" = "" ]; then
        echo "Please set stackage snapshot to use."
        echo "Acceptable formats are lts-15.1 or nightly-2020-4-5."
        exit 1
    fi

    if [ "$OUTPUT_DIR" = "" ]; then
        OUTPUT_DIR=$(pwd)
    fi

    if hash nixfmt 2>/dev/null; then
        FMT=nixfmt
    else
        FMT=cat
    fi
}

checkDeps() {
    if ! hash jq 2>/dev/null; then
        echo "jq isn't found in path. It is required for this script to work. Aborting."
        exit 1
    fi

    if ! hash yq 2>/dev/null; then
        echo "yq isn't found in path. It is required for this script to work. Aborting."
        exit 1
    fi

    if ! hash cabal2nix 2>/dev/null; then
        echo "cabal2nix isn't found in path. It is required for this script to work. Aborting."
        exit 1
    fi

    if hash nixfmt 2>/dev/null; then
        FMT=nixfmt
    else
        FMT=cat
    fi
}

checkDeps

while [ "$1" != "" ]; do
    case $1 in
        --cabal-hashes )        shift
                                CABAL_HASHES_DIR=$(realpath "$1")
                                ;;
        --snapshots )           shift
                                SNAPSHOTS_DIR=$(realpath "$1")
                                ;;
        --lts )                 shift
                                LTS="$1"
                                ;;
        --output )              shift
                                OUTPUT_DIR=$(realpath "$1")
                                ;;
    esac
    shift
done

checkOptions

mkdir -p "$OUTPUT_DIR/$LTS/"
pkgs=$(readBuildPlan "$LTS")

echo "$(makeDefaultNix $(getCompiler "$LTS"))" | $FMT > "$OUTPUT_DIR/$LTS/default.nix"
echo "$(makePackagesNix "$pkgs")" | $FMT > "$OUTPUT_DIR/$LTS/packages.nix"
echo "$(makeConfigurationPackages)" | $FMT > "$OUTPUT_DIR/$LTS/configuration-packages.nix"
