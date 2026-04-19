.PHONY: dev setup reset test check release release.run release.stop health review docs clean help

## Development

release: ## Build self-contained release (bundled ERTS, ~40 MB)
	MIX_ENV=prod mix deps.get --only prod
	MIX_ENV=prod mix compile
	MIX_ENV=prod mix assets.deploy
	MIX_ENV=prod mix release --overwrite

release.run: ## Run the built release locally (loopback, port 4000)
	_build/prod/rel/simulator/bin/simulator start

release.stop: ## Stop the running release
	_build/prod/rel/simulator/bin/simulator stop

prod: release release.run ## Alias: build + run release

dev: ## Start dev server with interactive shell
	iex -S mix phx.server

setup: ## Install deps, create DB, migrate, seed, build assets
	mix setup

reset: ## Drop DB, recreate, migrate, seed (fresh simulation)
	rm -f priv/sim_dev.db
	mix ecto.setup

## Testing & Quality

test: ## Run all tests
	mix test

check: ## Full pre-commit check (compile strict + format + lint + test)
	mix precommit && mix credo

## Simulation

health: ## Quick simulation health check
	@curl -s localhost:4000/api/health | python3 -m json.tool

review: ## Full simulation report
	@curl -s localhost:4000/api/report | python3 -m json.tool

pause: ## Pause the simulation
	@curl -s -X POST localhost:4000/api/sim/pause | python3 -m json.tool

resume: ## Resume the simulation
	@curl -s -X POST localhost:4000/api/sim/resume | python3 -m json.tool

fast: ## Set simulation to 5x speed
	@curl -s -X POST -H 'content-type: application/json' -d '{"interval_ms":200}' localhost:4000/api/sim/speed | python3 -m json.tool

docs: ## Generate ExDoc documentation
	mix docs

clean: ## Clean build artifacts
	mix clean
	rm -rf _build deps

## Help

help: ## Show this help
	@grep -E '^[a-zA-Z._-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
