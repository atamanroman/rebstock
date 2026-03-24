dev:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam' --watch &
    watchexec --restart --exts gleam -- gleam dev

css:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam' --minify

test:
    gleam test

build: css
    gleam build
