# BeamMP server image

Docker image for a [BeamMP](https://github.com/BeamMP/BeamMP-Server) (BeamNG.drive multiplayer) server.

The image contains the official Linux build of the BeamMP server, nothing else to download. Unlike most game servers, it doesn't need the game files or a Steam account.

## Requirements

- Docker
- An AuthKey from the [BeamMP Keymaster](https://keymaster.beammp.com/) (Keys, on the left)
- An `amd64` or `arm64` host

## Prebuilt image

CI builds the image for `amd64` and `arm64` and publishes it to Docker Hub as [`darco2903/beammp`](https://hub.docker.com/r/darco2903/beammp) on every push to `main`. Tags:

| Tag                | Contents                                     |
| ------------------ | -------------------------------------------- |
| `latest`           | Latest BeamMP release, built from `main`     |
| `<beammp version>` | That BeamMP release, e.g. `3.9.3`            |
| `sha-<commit>`     | Built from that commit of this repo          |

To build an older BeamMP version, run the workflow manually (Actions → Docker image → Run workflow) and give it the release tag.

To use it, replace `beammp` with `darco2903/beammp` in the commands below.

## Build

```sh
docker build -t beammp .
```

The latest stable BeamMP release is installed by default (pre-releases are skipped). To pin a version:

```sh
docker build --build-arg BEAMMP_RELEASE=tags/v3.9.3 -t beammp .
```

## Run

```sh
docker run -d -it --name beammp --stop-timeout 30 \
  -e BEAMMP_AUTH_KEY=your-auth-key \
  -v beammp-data:/beammp \
  -p 30814:30814/tcp -p 30814:30814/udp \
  beammp
```

On the first start, the server creates `ServerConfig.toml` and `Resources/` in the `beammp-data` volume. Keep `-it`: the server reads console commands from stdin.

Instead of `-e BEAMMP_AUTH_KEY`, the key can be set as `AuthKey` in `ServerConfig.toml`. The server writes the variables it was given into that file at each start, the key included.

## Server console

```sh
docker attach beammp
```

Type BeamMP commands (`help`, `status`, `list`, `say <message>`, `kick <name>`...), then detach with `Ctrl-P` `Ctrl-Q`. `exit` stops the server.

There's no history or tab completion: the server only gets them on a terminal, and in the image its console is a pipe (see [Stopping](#stopping)).

## Stopping

`docker stop beammp` (or `docker compose down`) shuts the server down gracefully, plugins' `onShutdown` included, like typing `exit`. Usually in about a second.

When its console isn't a terminal, BeamMP doesn't stop properly on its own: after `exit` it waits forever for its console to close, and SIGTERM kills it without the graceful shutdown. So `server.sh` gives the server a console pipe of its own, forwards stdin to it and closes it once the server logged `Shutdown.`, and turns `docker stop`'s SIGTERM into `exit`. Running the server some other way (e.g. overriding the entrypoint) brings both problems back.

In the Lua console (`lua`), `exit` only goes back to the normal console: `docker stop` then needs a second try, or the stop timeout kills the server.

## Configuration

### Environment variables

The server reads these itself. Each one overrides its setting in `ServerConfig.toml`, which is rewritten with it.

| Variable                   | `ServerConfig.toml`  | Description                                          |
| -------------------------- | -------------------- | ---------------------------------------------------- |
| `BEAMMP_AUTH_KEY`          | `AuthKey`            | Key from the Keymaster                               |
| `BEAMMP_NAME`              | `Name`               | Server name in the server list                       |
| `BEAMMP_DESCRIPTION`       | `Description`        | Server description                                   |
| `BEAMMP_MAP`               | `Map`                | e.g. `/levels/west_coast_usa/info.json`              |
| `BEAMMP_PORT`              | `Port`               | TCP and UDP port, `30814` by default                 |
| `BEAMMP_MAX_PLAYERS`       | `MaxPlayers`         |                                                      |
| `BEAMMP_MAX_CARS`          | `MaxCars`            | Per player                                           |
| `BEAMMP_PRIVATE`           | `Private`            | `true` hides it from the server list                 |
| `BEAMMP_TAGS`              | `Tags`               | Comma separated                                      |
| `BEAMMP_ALLOW_GUESTS`      | `AllowGuests`        |                                                      |
| `BEAMMP_LOG_CHAT`          | `LogChat`            |                                                      |
| `BEAMMP_DEBUG`             | `Debug`              |                                                      |
| `BEAMMP_RESOURCE_FOLDER`   | `ResourceFolder`     | `Resources` by default, relative to `/beammp`        |

The image also reads `DATA_DIR` (`/beammp`), the folder the server runs in.

### Volumes

| Path      | Contents                                                                                                |
| --------- | ------------------------------------------------------------------------------------------------------- |
| `/beammp` | `ServerConfig.toml`, `Resources/Client` (mods sent to players), `Resources/Server` (Lua plugins), `Server.log` |

The server runs as `beammp` (uid `1000`). A host folder mounted there must be writable by that uid.

### Ports

| Port        | Description                  |
| ----------- | ---------------------------- |
| `30814/tcp` | BeamMP server                |
| `30814/udp` | BeamMP server (vehicle data) |

If you change `Port` in `ServerConfig.toml` (or `BEAMMP_PORT`), publish that port instead, TCP and UDP.

## Docker Compose

`compose.yaml` builds the image and wires up the same volume and ports as the `docker run` command above.

```sh
cp .env.example .env     # then set BEAMMP_AUTH_KEY, or leave it empty and edit ServerConfig.toml
docker compose up -d
docker attach beammp     # server console; detach with Ctrl-P Ctrl-Q
docker compose down      # stops the server gracefully
```

The data volume is named `beammp-data`, the same as in the `docker run` command, so you can switch between Compose and `docker run` without losing data.

To edit `ServerConfig.toml` or add mods, mount a host folder at `/beammp` instead of the volume (owned by uid `1000`), or copy files with `docker cp`.

## With the server manager

The server manager runs this image with its own entrypoint, shared by all its game images, and `/server.sh` as the command. The manager's entrypoint handles the console FIFO, the log and the stop command on `docker stop`; `server.sh` runs the server in the foreground and, from its console, stops it properly (see [Stopping](#stopping)). It works with the manager's `read_only` root and dropped capabilities: the server only writes in `/beammp` and `/tmp`.

The BeamMP folder is a host folder, `/opt/games/beammp/<name>/server`, so the file manager can edit `ServerConfig.toml` and the mods and plugins in `Resources/`. A service for `deploy/games/compose.yml`, `beammp@example` here:

```yaml
  game-beammp-example:
    <<: *game
    image: darco2903/beammp
    container_name: game-beammp-example
    command: ["/server.sh"]
    healthcheck:
      # Ready once the server printed that everything started
      test: ["CMD-SHELL", "grep -q 'ALL SYSTEMS STARTED' \"/var/log/web-manager/$$SERVICE/last.log\""]
      interval: 5s
      start_period: 60s
      start_interval: 2s
    environment:
      SERVICE: beammp@example
      GAME_UID: "1000" # beammp in the image, whatever its name on the host
      GAME_GID: "1025" # game-manager
      GAME_GROUPS: "1025,1000"
      STOP_COMMAND: exit
    # Port of ServerConfig.toml, one per server, TCP and UDP
    ports:
      - "30814:30814/tcp"
      - "30814:30814/udp"
    volumes:
      - *entrypoint
      # The folder of the file manager: ServerConfig.toml and Resources/
      - /opt/games/beammp/example/server:/beammp
      - /run/web-manager/beammp@example:/run/web-manager/beammp@example
      - /var/log/web-manager/beammp@example:/var/log/web-manager/beammp@example
```

Then create the folder and the container:

```sh
sudo install -d -o 1000 -g 1000 -m 770 /opt/games/beammp/example/server
sudo web-manager-perms --fix
docker compose -f deploy/games/compose.yml create game-beammp-example
```

Put the AuthKey in `ServerConfig.toml` with the file manager (the server creates the file on its first start, then stops after 10 seconds without a key), or as `BEAMMP_AUTH_KEY` in `environment:`.

## Updating

Rebuild the image (`--no-cache` to pick up a new `latest`, or bump `BEAMMP_RELEASE`) or pull the new one, then recreate the container. `ServerConfig.toml`, mods and plugins stay in the volume. The server prints a message at startup when a newer BeamMP release exists.

## License

This repo's files are under the MIT license (`LICENSE`). The image also contains the [BeamMP server](https://github.com/BeamMP/BeamMP-Server), which is AGPL-3.0. Its license and a link to the matching source are in the image at `/usr/share/licenses/beammp/`. BeamNG.drive itself isn't in the image.

## Troubleshooting

- **`No AuthKey specified`, then `Closing in 10 seconds`:** set `BEAMMP_AUTH_KEY`, or `AuthKey` in `ServerConfig.toml`.
- **`AuthKey specified is the wrong length`:** the key is 36 characters, copied from the Keymaster as is.
- **Players can't connect:** publish the port of `ServerConfig.toml` for both TCP and UDP, and open it in the host's firewall.
- **`Failed to create/write to config file`:** `/beammp` isn't writable by uid `1000`. Check the owner of the host folder mounted there.
