puts() { printf %s\\n "$@" ;}
pute() { printf %s\\n "!! $*" >&2 ;}
argq() { [ $# -gt 0 ] && printf "'%s' " "$@" ;}

jq_bin="$(npm prefix)/node_modules/node-jq/bin/jq"
pj() {
   "$jq_bin" -e "$@" package.json
}
jqinplace() {
   file="$2"
   "$jq_bin" -e "$@" | sponge "$file"
}

dump_status() {
   cat <<EOF > .deploy-status.env
STEP="$STEP"
NEW_VERSION="$NEW_VERSION"
OLD_VERSION="$OLD_VERSION"
EOF
}


# Script setup & resumption
# ------ ----- - ----------

if [ -r .deploy-status.env ]; then
   puts ''
   puts 'These values were found in `.deploy-status.env`:'
   puts ''
   cat .deploy-status.env
   puts ''

   printf %s 'Load them and attempt to continue an aborted deployment? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      source .deploy-status.env
      export STEP NEW_VERSION OLD_VERSION
   else
      rm .deploy-status.env
      exit 3
   fi
fi

if [ -z "$STEP" ]; then
   if [ $# -ge 1 ]; then
      STEP="$1"
   else
      STEP=1
   fi
fi

if [ -z "$NEW_VERSION" ]; then
   if [ $# -ge 2 ]; then
      NEW_VERSION="$2"
      puts 'New version: '"v$NEW_VERSION"
   else
      NEW_VERSION="$(pj -r .version)"
      puts 'New version (from `bs-deriving/package.json`):  '"v$NEW_VERSION"
   fi
fi

if [ -z "$OLD_VERSION" ]; then
   if [ $# -ge 3 ]; then
      OLD_VERSION="$2"
      puts 'Old version: '"v$OLD_VERSION"
   else
      OLD_VERSION="$(cd ./ppx-deriving; pj -r .version)"
      puts 'Old version (from `ppx-deriving/package.json`): '"v$OLD_VERSION"
   fi
fi

if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
   pute 'The version in `bs-deriving` doesn'\''t appear to have been bumped!'
   puts '' >&2

   pute 'You may have called this directly by accident; this script is intended to be'
   pute 'called from the `version` lifecycle. Try the following, instead:'
   puts '' >&2
   puts '      npm version patch --no-git-tag-version' >&2
   puts '' >&2
   exit 2
fi


# Steps
# -----
step_1() {
   STEP=1 && dump_status

   puts ''
   printf %s 'Update bsconfig.json to match? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      jqinplace ".version = \"$NEW_VERSION\"" bsconfig.json || exit 127
   else
      exit 4
   fi

   step_2
}


step_2() {
   STEP=2 && dump_status

   puts ''
   printf %s 'Update ppx-deriving/package.json to match? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         npm version --no-git-tag-version "$NEW_VERSION" && \
         git add package.json bsconfig.json package-lock.json) || exit 127
   else
      exit 4
   fi

   step_3
}


step_3() {
   STEP=3 && dump_status

   puts ''
   printf %s 'Remove previous artifacts and checksums from ppx-deriving? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving &&
         git clean -Xdf;
      git rm SHASUM256.txt )
   else
      exit 4
   fi

   step_4
}


step_4() {
   STEP=4 && dump_status

   puts ''
   (  cd ./ppx-deriving && \
      git status )
   printf %s 'Commit new, unpopulated version of ppx-deriving with these changes? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         git commit -m "(- rel NF) Prep for v$NEW_VERSION" ) || exit 127
      git add ./ppx-deriving || exit 127
   else
      exit 4
   fi

   step_5
}


step_5() {
   STEP=5 && dump_status

   puts ''
   git add package.json package-lock.json bsconfig.json || exit 127
   git status
   printf %s 'Further, commit these changes to a new version of bs-deriving as well? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      git commit -m "(rel) v$NEW_VERSION" || exit 127
   else
      exit 4
   fi

   step_6
}


step_6() {
   STEP=6 && dump_status

   puts ''
   git --no-pager show
   printf %s "Tag this changeset as 'v$NEW_VERSION'? [Y/n] "; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      git tag "v$NEW_VERSION" --file=- <<MSG || exit 127
Version $NEW_VERSION of ppx_deriving packaged for BuckleScript.

Of note, the corresponding version of \`ppx-deriving\` is *not* included, due to a recursively mutual dependency. These packages are, however, properly packaged on npm:

    npm install --save bs-deriving@$NEW_VERSION
    npm install --save-dev ppx-deriving@$NEW_VERSION

If you wish to acquire them via git, ensure you manually pull the matching version of my \`ppx-deriving\` package! The submodule linkage recorded in the repository will be perpetually one release behind.
MSG
   else
      exit 4
   fi

   step_7
}


step_7() {
   STEP=7 && dump_status

   puts ''
   printf %s 'Push these changes to GitHub, so Travis can start building the artifacts? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         git push ) || exit 127
      git push --tags || exit 127
      git push || exit 127
   else
      exit 4
   fi

   step_8
}


step_8() {
   STEP=8 && dump_status

   puts ''
   puts "When the Travis build is done, if successful, it'll upload the artifacts to a GitHub 'draft.'"
   puts "You'll need to visit the Releases page and hit 'Publish release' on that draft, before continuing:"
   puts '   https://github.com/ELLIOTTCABLE/bs-deriving/releases'
   puts ''

   printf %s 'Start checking for those build artifacts on GitHub? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      until (
         cd ./ppx-deriving && \
         make SHASUM256.txt
      ); do puts ''; sleep 15; done
   else
      exit 4
   fi

   step_9
}


step_9() {
   STEP=9 && dump_status

   puts ''
   (  cd ./ppx-deriving && \
      git add SHASUM256.txt ) || exit 127
   (  cd ./ppx-deriving && \
      git --no-pager diff --cached )
   printf %s 'Success! Now, commit the updated checksum to ppx-deriving, and tag? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         git commit -m "(rel) v$NEW_VERSION" && \
         git tag "v$NEW_VERSION" ) || exit 127
      git add ./ppx-deriving || exit 127
   else
      exit 4
   fi

   step_10
}


step_10() {
   STEP=10 && dump_status

   puts ''
   (  cd ./ppx-deriving && \
      npm pack && \
      rm "ppx-deriving-$NEW_VERSION.tgz" ) || exit 127
   printf %s "Publish 'ppx-deriving@$NEW_VERSION' to npm? [Y/n] "; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         npm publish ) || exit 127
   else
      exit 4
   fi

   step_11
}


step_11() {
   STEP=11 && dump_status

   puts ''
   printf %s "Update superproject's dependency on ppx-deriving? [Y/n] "; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      jqinplace '.devDependencies["ppx-deriving"] = "=" + .version' package.json || exit 127
      rm -rf node_modules/ppx-deriving && \
         npm install --package-lock-only && \
         npm link ./ppx-deriving || exit 127
      git add package.json package-lock.json || exit 127
   else
      exit 4
   fi

   step_12
}


step_12() {
   STEP=12 && dump_status

   puts ''
   git status
   printf %s 'Commit updated dependency and checksummed ppx to superproject? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      git commit -m "(- rel up sub) Fast-forward to artifact-checksummed v$NEW_VERSION of ppx" || exit 127
   else
      exit 4
   fi

   step_13
}


step_13() {
   STEP=13 && dump_status

   puts ''
   printf %s 'Push the final, linked commits upstream? [Y/n] '; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      (  cd ./ppx-deriving && \
         git push && \
         git push --tags ) || exit 127
      git push || exit 127
   else
      exit 4
   fi

   step_14
}


step_14() {
   STEP=14 && dump_status

   puts ''
   npm pack && \
      rm "bs-deriving-$NEW_VERSION.tgz" || exit 127
   printf %s "Publish 'bs-deriving@$NEW_VERSION' to npm? [Y/n] "; read yn
   if [ "$yn" != "${yn#[Yy]}" ]; then
      npm publish || exit 127
   else
      exit 4
   fi

   # there is no step 15! ... lol.
   rm .deploy-status.env
}


# Step dispatch
# ---- --------
eval "'step_$STEP'"
