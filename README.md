# Rebstock - Self Hosted Wine Inventory

> [!CAUTION]
> This is mostly vibe coded (for now).
> Not that I like it, but I
>
> 1) want to experiment with agentic coding
> 1) want to prototype quickly to learn what works for me (and my wines) before I start polishing anything
> 1) am very curious about [Gleam](https://gleam.run)
> 1) don't consider user interfaces one of my "strengths".
>
> Features stick with my workflow will be cleaned up properly and the DB schema is carefully reviewed to provide some stability.

## Stack

- Gleam with Wisp/Mist
- SQLite
- Tailwind CSS and HTMX
- just as taskrunner
- nix for deployment

## Installation

There's a [flake.nix](./flake.nix) for installation on nix based systems.

TODO: add sample from my dotfiles

## Configuration

See [config.example.json](./config.example.json).
The referenced JSON schema serves as documentation.

### Authentication

There's no authentication if started in single-user mode.
Every request will be authenticated automatically as the user you've configured.

```
"auth": {
  "single": {
    "user": "admin"
  }
}
```

## Development

`just dev` will start the service on [localhost:3000](http://localhost:3000) and import my last Vivino export from [./vivino_data](./vivino_data) to seed the DB.
You can get your own export from Vivino at [vivino.com/settings -> Account Management -> Export your data](https://www.vivino.com/settings).

`just setup-dev` will check if all dev tools are available and install Git pre-commit format hook.

If you're on nix, `nix develop` will drop you in a dev shell with all development tools present.
