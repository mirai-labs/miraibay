import typer
from datetime import datetime, UTC
from decimal import Decimal
from pysui import SuiConfig, SyncClient, handle_result
from pysui.sui.sui_txn.sync_transaction import SuiTransaction
from pysui.sui.sui_types import ObjectID, SuiString, SuiU64
from rich import print

PACKAGE_ID = "0x34d656894723daac48f3f825ae3b35c428e7b4cb5c65b08bb33349475a1e23ac"

app = typer.Typer()

# mbay auction create 'Prime Machin x Arttoo' --description 'This is a collaboration between Studio Mirai and Arttoo' --start-ts 0 --end-ts 1753660800000 --reserve-price 1000000000

config = SuiConfig.default_config()
client = SyncClient(config)


@app.command()
def bid(
    auction_id: str = typer.Argument(...),
    amount: int = typer.Argument(..., help="Amount to bid in MIST (1 SUI = 1_000_000_000 MIST)."),
):  # fmt: skip
    txer = SuiTransaction(
        client=client,
        compress_inputs=True,
        merge_gas_budget=True,
    )
    payment = txer.split_coin(
        coin=txer.gas,
        amounts=[amount],
    )
    txer.move_call(
        target=f"{PACKAGE_ID}::auction::bid",
        arguments=[
            ObjectID(auction_id),
            payment,
            ObjectID("0x6"),
        ],
    )
    result = handle_result(
        txer.execute(gas_budget=1_000_000_000),
    )
    print(result)

    return


@app.command()
def create(
    name: str = typer.Argument(..., help="Name of the auction."),
    description: str = typer.Option(None, help="Description of the auction."),
    start_ts: int = typer.Option(..., help="Start timestamp of the auction."),
    end_ts: int = typer.Option(..., help="End timestamp of the auction."),
    reserve_price: int = typer.Option(0, help="Reserve price of the auction in MIST (1 SUI = 1_000_000_000 MIST)."),
    starting_price: int = typer.Option(0, help="Starting price of the auction in MIST (1 SUI = 1_000_000_000 MIST)."),
    min_bid_increment: int = typer.Option(0, help="Minimum bid increment of the auction in MIST (1 SUI = 1_000_000_000 MIST)."),
):  # fmt: skip
    if start_ts == 0:
        start_ts = int(datetime.now(UTC).timestamp() * 1000)
    if start_ts > end_ts:
        raise typer.Exit("Start timestamp must be before end timestamp.")

    print(f"Name: {name}")
    print(f"Description: {description}")
    print(f"Start timestamp: {start_ts} ({datetime.fromtimestamp(start_ts / 1000, UTC).isoformat()})")  # fmt: skip
    print(f"End timestamp: {end_ts} ({datetime.fromtimestamp(end_ts / 1000, UTC).isoformat()})")  # fmt: skip
    print(f"Reserve price: {Decimal(reserve_price) / 1_000_000_000} SUI")
    typer.confirm("Please confirm the auction details:")

    txer = SuiTransaction(
        client=client,
        compress_inputs=True,
    )
    description_opt = txer.move_call(
        target="0x1::option::some" if description else "0x1::option::none",
        arguments=[SuiString(description)] if description else [],
        type_arguments=["0x1::string::String"],
    )
    auction, auction_manager_cap = txer.move_call(
        target=f"{PACKAGE_ID}::auction::new",
        arguments=[
            SuiString(name),
            description_opt,
            SuiU64(start_ts),
            SuiU64(end_ts),
            SuiU64(reserve_price),
            SuiU64(starting_price),
            SuiU64(min_bid_increment),
        ],
    )
    txer.move_call(
        target="0x2::transfer::public_share_object",
        arguments=[auction],
        type_arguments=[f"{PACKAGE_ID}::auction::Auction"],
    )
    txer.transfer_objects(
        transfers=[auction_manager_cap],
        recipient=config.active_address,
    )
    result = handle_result(
        txer.execute(gas_budget=1_000_000_000),
    )
    print(result)

    return
