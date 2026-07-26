for c in $(brew list --cask); do
  brew install --cask --force "$c"
done