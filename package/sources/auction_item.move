module miraibay::auction_item {

    use std::string::{String};

    use sui::display::{Self};
    use sui::package::{Self};

    public struct AUCTION_ITEM has drop {}

    // A placeholder NFT that can be used as an auction item.
    // This is useful to capture post-auction intent in situations
    // where the actual object can't be provided.
    public struct AuctionItem has key, store {
        id: UID,
        name: String,
        description: Option<String>,
        creator: address,
        image_url: Option<String>,
        url: Option<String>,
        attribute_keys: vector<String>,
        attribute_values: vector<String>,
    }

    fun init(
        otw: AUCTION_ITEM,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let mut display = display::new<AuctionItem>(&publisher, ctx);
        display.add(b"name".to_string(), b"{name}".to_string());
        display.add(b"description".to_string(), b"{description}".to_string());
        display.add(b"creator".to_string(), b"{creator}".to_string());
        display.add(b"image_url".to_string(), b"{image_url}".to_string());
        display.add(b"url".to_string(), b"{url}".to_string());
        display.add(b"attribute_keys".to_string(), b"{attribute_keys}".to_string());
        display.add(b"attribute_values".to_string(), b"{attribute_values}".to_string());

        transfer::public_transfer(display, ctx.sender());
        transfer::public_transfer(publisher, ctx.sender());
    }

    public fun new(
        name: String,
        description: Option<String>,
        image_url: Option<String>,
        url: Option<String>,
        attribute_keys: vector<String>,
        attribute_values: vector<String>,
        ctx: &mut TxContext,
    ): AuctionItem {
        let item = AuctionItem {
            id: object::new(ctx),
            name: name,
            description: description,
            creator: ctx.sender(),
            image_url: image_url,
            url: url,
            attribute_keys: attribute_keys,
            attribute_values: attribute_values,
        };
        item
    }

    public fun drop(
        item: AuctionItem,
    ) {
        let AuctionItem {
            id,
            name: _,
            description: _,
            creator: _,
            image_url: _,
            url: _,
            attribute_keys: _,
            attribute_values: _,
        } = item;
        id.delete();
    }
}  