puts() { printf %s\\n "$@" ;}
pute() { printf %s\\n "!! $*" >&2 ;}
argq() { [ $# -gt 0 ] && printf "'%s' " "$@" ;}


if ! command -v sponge >/dev/null; then
   pute 'You need `sponge` to use this script!'
   pute 'Try: `brew install moreutils`'
   puts '' >&2
   missing_dep=true
fi

if [ -n "$missing_dep" ]; then exit 3; fi

(
   cd ./ppx-deriving;
   if ! git diff --exit-code >/dev/null || ! git diff --cached --exit-code >/dev/null; then
      pute 'There appear to be uncommitted changes in `ppx-deriving`. You should ensure the'
      pute 'submodule is entirely committed and clean before attempting to version-bump'
      pute 'the superproject.'
      puts '' >&2

      pute 'Try:'
      puts '' >&2
      puts '      (cd ./ppx-deriving && git stash save)' >&2
      puts '' >&2
      exit 2
   fi
)

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "master" ]; then
   pute "You're on a topic branch, '$branch'."
   puts '' >&2

   pute "You need to merge your work into 'master' before you can version-bump,"
   pute 'commit, and push.'
   puts '' >&2

   pute 'Try:'
   puts '' >&2
   puts '      git checkout master' >&2
   puts "      git merge --ff '$branch'" >&2
   puts '' >&2
   exit 2
fi
