sudo killall jcu
git checkout -f -- .
git pull origin master
brunch build ./resources/static/brunch
make deps
make
