set -e

puts() { printf %s\\n "$@" ;}
pute() { printf %s\\n "~~ $*" >&2 ;}
argq() { [ $# -gt 0 ] && printf "'%s' " "$@" ;}

# An alternative to `set +o xtrace` that doesn't print the unset line.
x () { puts '`` '"$*" >&2 ; "$@" || exit $? ;}

if [ -z "$STAGE" ] || [ -z "$COMPONENT" ]; then
   pute 'This script is intended to be called in a CI environment with a current $STAGE,'
   pute 'and a $COMPONENT to build. e.g.'

   puts '' >&2
   puts '      STAGE=install COMPONENT=runtime npm run travis' >&2
   puts '' >&2
   exit 2
fi

# Helpers
# -------
install_matching_ocaml() {
   x wget https://raw.githubusercontent.com/ocaml/ocaml-ci-scripts/master/.travis-ocaml.sh

   BSC_VERSION="$(bsc -vnum)"

   case "$BSC_VERSION" in
      *OCaml4.02.3*) export OCAML_VERSION=4.02 OPAM_SWITCH=ocaml-base-compiler.4.02.3;;
      *OCaml4.06.1*) export OCAML_VERSION=4.06 OPAM_SWITCH=ocaml-base-compiler.4.06.1;;
      *)
         pute 'Unrecognized `bsc` version: '"$BSC_VERSION"
         exit 10
      ;;
   esac

   puts 'export OPAM_SWITCH='"$OPAM_SWITCH"
   x bash -ex .travis-ocaml.sh
   x opam pin -y -n add ppx_deriving .
   x opam install -y --deps-only --with-test ppx_deriving
   eval `opam config env`

   if [ -n "$VERBOSE" ]; then
      x opam config env
      x opam list
   fi
}

# Stages
# ------
stage_install() {
   # Enable configurable debugging without adding new commits. (If something goes wrong,
   # you can set $VERBOSE to some value inside Travis's configuration, and then hit
   # "rebuild".)
   if [ -n "$VERBOSE" ]; then
      x npm config set loglevel verbose
   fi

   x git fetch --tags

   # Install npm dependencies, but avoid invoking our own `prepare` script
   x npm ci --ignore-scripts

   # Now we either select a particular `bs-platform` to install, or manually process the
   # `postinstall` script of the one we installed above.
   if [ -n "$GENERATION" ]; then
      x npm install "bs-platform@$GENERATION"
   else
      x npm rebuild bs-platform
   fi

   # ‘Install’ our own local version of the ppx-binary package
   x npm link ./ppx-*

   # Finally, we need a working OCaml installation of the same version as the BuckleScript we just
   # built.
   install_matching_ocaml
}

stage_test() {
   eval `opam config env`

   case "$COMPONENT" in
      runtime)
         x npm run --silent build:runtime
      ;;
      ppx-examples-test)
         x npm run --silent build:examples
         x npm run --silent test
      ;;
   esac
}

stage_deploy() {
   eval `opam config env`

   x npm run --silent build:ppx
}

# Invocation
# ----------
case "$STAGE" in
   install) stage_install ;;
   test) stage_test ;;
   deploy) stage_deploy ;;
esac
