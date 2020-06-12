#!/bin/sh

# apt install devscripts git
set -ex

ROOT_DIR="$PWD"
UPSTREAM_REPO="$ROOT_DIR/gh-qcad-upstream"
LAUNCHPAD_SRC_REPO="$ROOT_DIR/lp-qcad-stable"
LAUNCHPAD_PKG_REPO="$ROOT_DIR/lp-qcad-packaging"

fetch () {
  ## Update upstream repo
  cd $UPSTREAM_REPO
  git checkout master
  git pull
  check_updates
}

check_updates () {
  ## Look for last release date
  LAST_RELEASE_DATE=`dpkg-parsechangelog --file $LAUNCHPAD_PKG_REPO/changelog --show-field Changes | grep "Release date" | sed -e 's/ *Release date: //'`
  # HACK: git log --after is not really "after" but "since" (ie. it includes current date)
  # So we grab date, then add one second...
  LAST_RELEASE_DATE_SECS=$(date +%s --date="$LAST_RELEASE_DATE")
  LAST_RELEASE_DATE_AFTER=$(date --rfc-2822 --date="@$(($LAST_RELEASE_DATE_SECS + 1))")
  # Retrieve tag information
  cd $UPSTREAM_REPO
  git checkout master
  NEXT_TAGS=`git log --tags --simplify-by-decoration --reverse --after="$LAST_RELEASE_DATE_AFTER" --pretty="tformat:%H #%d # %cD"`
  NEXT_TAGS_COUNT=$(echo "$NEXT_TAGS" | grep -c -e '^.* # .* # .*$' || true)

  if [ "$NEXT_TAGS_COUNT" -eq 0 ]
  then
    echo "There is no new tag to proceed, bye!"
    exit 0
  fi

  echo "There is $NEXT_TAGS_COUNT tag(s) that have not been packaged (since $LAST_RELEASE_DATE):"
  echo "$NEXT_TAGS"
  echo ""
  echo "Please remember that only one tag is proceed at a time, please re-run if you want to proceed new tag..."

  IFS='
'
  for tag in $NEXT_TAGS; do
    echo $tag
    NEXT_RELEASE_VERSION=$( echo $tag | sed -r 's/^([^#]+) # \((HEAD, |)tag: v([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(, .*, master|)\) # ([^#]+)$/\3/' )
    if [ "$NEXT_RELEASE_VERSION" = "$tag" ]; then
      echo "Skipping '$tag': its not a release"
    else
      NEXT_TAG="$tag"
      break
    fi
  done
}

merge_upstream_to_launchpad () {
  if [ -z $NEXT_RELEASE_VERSION ]; then
    check_updates
  fi
  NEXT_GIT_TAG="v$NEXT_RELEASE_VERSION"
  echo "Processing Git tag: $NEXT_GIT_TAG ..."
  cd $UPSTREAM_REPO

  ( cd $UPSTREAM_REPO && git checkout $NEXT_GIT_TAG && grep R_QCAD_VERSION_STRING $UPSTREAM_REPO/src/core/RVersion.h )
  RSYNC_LOG=$( rsync -rv --delete-after --exclude '.gitignore' --exclude '.git' --exclude '.bzr' $UPSTREAM_REPO/ $LAUNCHPAD_SRC_REPO/ )

  DELETED_FILES=$(echo "$RSYNC_LOG" | grep  '^deleting ' | sed -e 's/^deleting \(.*\)/\1/')

  cd $LAUNCHPAD_SRC_REPO
  git status
  git add .
  git commit -m"Import QCAD $NEXT_RELEASE_VERSION"

  echo "Warning: your modifications have been committed but not pushed"
  echo "> (cd $LAUNCHPAD_SRC_REPO && git push)"
}

update_debian_changelog () {
  if [ -z $NEXT_RELEASE_VERSION ]; then
    check_updates
  fi

  NEXT_TAG_DATE=$( echo $NEXT_TAG | sed -r 's/^([^#]+) # \((HEAD, |)tag: v([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(, .*, master|)\) # ([^#]+)$/\5/' )
  if [ "$NEXT_TAG_DATE" = "$NEXT_TAG" ]; then
    echo "Failed to extract date from $NEXT_TAG"
    exit 1
  fi

  NEXT_TAG_HASH=$( echo $NEXT_TAG | sed -r 's/^([^#]+) # \((HEAD, |)tag: v([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(, .*, master|)\) # ([^#]+)$/\1/' )
  if [ "$NEXT_TAG_HASH" = "$NEXT_TAG" ]; then
    echo "Failed to extract hash from $NEXT_TAG"
    exit 1
  fi

  DCH_ENTRY_MSG="New upstream release\n\n    Release date: $NEXT_TAG_DATE\n    Git tag hash: $NEXT_TAG_HASH"

  DEBEMAIL="neomilium@gmail.com" DEBFULLNAME="Romuald Conty" dch \
    --newversion "$NEXT_RELEASE_VERSION-1" \
	--upstream \
	--changelog $LAUNCHPAD_PKG_REPO/changelog \
	--distribution unstable \
	--urgency low \
	"XXX"

  sed -i $LAUNCHPAD_PKG_REPO/changelog -e "s/XXX/$DCH_ENTRY_MSG/"

  cd $LAUNCHPAD_PKG_REPO
  git diff changelog || true
  git add changelog
  git commit -m"New upstream release: $NEXT_RELEASE_VERSION"
  echo "Warning: your modifications have been committed but not pushed"
  echo "> (cd $LAUNCHPAD_PKG_REPO && git push)"
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [list|update|merge|push]"
  exit 1
fi

case "$1" in
  update)
    fetch
	check_updates
  ;;
  list)
    check_updates
  ;;
  merge)
    merge_upstream_to_launchpad
    update_debian_changelog
  ;;
  push)
    (cd $LAUNCHPAD_SRC_REPO && git push)
    (cd $LAUNCHPAD_PKG_REPO && git push)
  ;;
  debian)
    update_debian_changelog
  ;;
esac
