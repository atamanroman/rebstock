dev:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css' --watch &
    watchexec --restart --exts gleam -- gleam dev

css:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css' --minify

test:
    gleam test

build: css
    gleam build
