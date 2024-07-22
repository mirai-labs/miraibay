module miraibay::auction_old {
    
    use std::string::{String};
    use std::type_name::{Self, TypeName};

    use sui::balance::{Self, Balance};
    use sui::clock::{Clock};
    use sui::coin::{Self, Coin};
    use sui::display::{Self};
    use sui::event;
    use sui::package::{Self};
    use sui::sui::{SUI};
    use sui::table_vec::{Self, TableVec};
    use sui::transfer::{Receiving};
    use sui::vec_map::{Self, VecMap};

    public struct AUCTION_OLD has drop {}

    public struct Auction has key, store {
        id: UID,
        name: String,
        description: Option<String>,
        seller: address,
        item_refs: VecMap<ID, TypeName>,
        starts_at_ts: u64,
        ends_at_ts: u64,
        reserve_price: u64,
        starting_price: u64,
        min_bid_increment: u64,
        bid: Option<Bid>,
        winner: Option<address>,
        history: TableVec<BidRecord>,
    }

    public struct AuctionManagerCap has key, store {
        id: UID,
        auction_id: ID,
    }

    public struct AuctionCreatedEvent has copy, drop {
        auction_id: ID,
    }

    public struct Bid has store {
        bidder: address,
        timestamp: u64,
        value: Balance<SUI>,
    }

    public struct BidRecord has store {
        bidder: address,
        timestamp: u64,
        value: u64,
    }

    public struct ClaimItemCap has key, store {
        id: UID,
        auction_id: ID,
        item_id: ID,
        item_typename: TypeName
    }

    const EAuctionIsClosed: u64 = 1;
    const EAuctionNotStarted: u64 = 2;
    const EAuctionNotEnded: u64 = 3;
    const EInvalidAuctionManagerCap: u64 = 4;
    const EInvalidClaimItemCap: u64 = 5;

    const MAX_ITEM_COUNT: u8 = 255;

    fun init(
        otw: AUCTION_OLD,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let mut display = display::new<Auction>(&publisher, ctx);
        display.add(b"name".to_string(), b"{name}".to_string());
        display.add(b"description".to_string(), b"{description}".to_string());
        display.add(b"seller".to_string(), b"{seller}".to_string());
        display.add(b"starts_at_ts".to_string(), b"{starts_at_ts}".to_string());
        display.add(b"ends_at_ts".to_string(), b"{ends_at_ts}".to_string());
        display.add(b"is_closed".to_string(), b"{is_closed}".to_string());
        display.add(b"reserve_price".to_string(), b"{reserve_price}".to_string());
        display.add(b"starting_price".to_string(), b"{starting_price}".to_string());
        display.add(b"min_bid_increment".to_string(), b"{min_bid_increment}".to_string());

        transfer::public_transfer(display, ctx.sender());
        transfer::public_transfer(publisher, ctx.sender());
    }

    // TODO: Implement refund if manager doesn't win.
    public fun close(
        cap: &AuctionManagerCap,
        auction: &mut Auction,
        ctx: &mut TxContext,
    ) {
        assert_auction_manager_cap(cap, auction);

        // Extract and unwrap the bid.
        let last_bid = auction.bid.extract();
        let Bid {
            bidder,
            timestamp: _,
            value,
        } = last_bid;
        
        // Initialize the auction winner to caller's address. Since this requires AuctionManagerCap,
        // the winner will be initialized to the creator of the auction.
        auction.winner.fill(ctx.sender());
        // If the winning bid's value exceeds the reserve price, set the 
        // winner to the address of the biider.
        if (value.value() > auction.reserve_price) {
            auction.winner.swap_or_fill(bidder);
        };
        
        while (!auction.item_refs.is_empty()) {
            let (item_id, item_typename) = auction.item_refs.remove_entry_by_idx(0);
            let claim_item_cap = ClaimItemCap {
                id: object::new(ctx),
                auction_id: object::id(auction),
                item_id: item_id,
                item_typename: item_typename,
            };
            transfer::public_transfer(claim_item_cap, *auction.winner.borrow());
        };

        let payment = coin::from_balance(value, ctx);
        //if (auction.winner.borrow() == ctx.sender()) {
        //    transfer::public_transfer(payment, ctx.sender());
        //};
    }

    public fun add_item<T: key + store>(
        cap: &AuctionManagerCap,
        auction: &mut Auction,
        item: T,
        clock: &Clock,
    ) {
        assert_auction_manager_cap(cap, auction);
        assert_auction_not_started(auction, clock);
        assert!(auction.item_refs.size() as u8 < MAX_ITEM_COUNT);
        auction.item_refs.insert(object::id(&item), type_name::get<T>());
        transfer::public_transfer(item, auction.id.to_address());
    }

    public fun claim_item<T: key + store>(
        cap: ClaimItemCap,
        auction: &mut Auction,
        item_to_receive: Receiving<T>,
        ctx: &mut TxContext,
    ) {
        assert!(cap.auction_id == object::id(auction), EInvalidClaimItemCap);
        assert!(cap.item_id == transfer::receiving_object_id(&item_to_receive), EInvalidClaimItemCap);
        assert!(cap.item_typename == type_name::get<T>(), EInvalidClaimItemCap);

        let item = transfer::public_receive(&mut auction.id, item_to_receive);
        auction.item_refs.remove(&object::id(&item));
        transfer::public_transfer(item, ctx.sender());
        
        let ClaimItemCap {
            id,
            auction_id: _,
            item_id: _,
            item_typename: _,
        } = cap;
        id.delete();
    }

    public fun destroy_empty(
        auction: Auction,
    ) {
        let Auction {
            id,
            name: _,
            description: _,
            seller: _,
            item_refs,
            starts_at_ts: _,
            ends_at_ts: _,
            reserve_price: _,
            starting_price: _,
            min_bid_increment: _,
            winner: _,
            bid,
            history,
        } = auction;
        id.delete();
        item_refs.destroy_empty();
        bid.destroy_none();
        history.destroy_empty();
    }

    fun assert_auction_manager_cap(
        cap: &AuctionManagerCap,
        auction: &Auction,
    ) {
        assert!(cap.auction_id == object::id(auction), EInvalidAuctionManagerCap);
    }

    fun assert_auction_not_ended(
        auction: &Auction,
        clock: &Clock,
    ) {
        assert!(clock.timestamp_ms() < auction.ends_at_ts, EAuctionNotEnded);
    }
    
    fun assert_auction_not_started(
        auction: &Auction,
        clock: &Clock,
    ) {
        assert!(clock.timestamp_ms() > auction.starts_at_ts, EAuctionNotStarted);
    }
}