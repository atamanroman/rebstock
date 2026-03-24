dev:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam' --watch &
    REBSTOCK_SEED=1 watchexec --restart --exts gleam -- gleam run

css:
    ./tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam' --minify

test:
    gleam test

build: css
    gleam build
