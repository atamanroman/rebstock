dev:
    watchexec --restart --exts gleam,css -- just _dev

_dev:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css'
    gleam dev

css:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css' --minify

test:
    gleam test

build: css
    gleam build
