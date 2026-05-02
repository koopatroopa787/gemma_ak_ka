.PHONY: setup registry test benchmark lint format

setup:
	pip install -r requirements.txt

registry:
	python registry/registry_builder.py --build

test:
	pytest tests/ -v

benchmark:
	python benchmark.py --image data/authentic/sample.jpg

lint:
	ruff check .

format:
	ruff format .
