import typer
from miraibay_cli.commands import auction

app = typer.Typer()

app.add_typer(auction.app, name="auction")
