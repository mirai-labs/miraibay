module miraibay::auction {
    
    use std::string::{String};
    use std::type_name::{Self, TypeName};

    use sui::balance::{Self, Balance};
    use sui::clock::{Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::table_vec::{Self, TableVec};
    use sui::transfer::{Self, Receiving};
    use sui::vec_map::{Self, VecMap};

    public struct Auction has key, store {
        id: UID,
        name: String,
        item_refs: VecMap<ID, TypeName>,
        starts_at_ts: u64,
        ends_at_ts: u64,
        is_closed: bool,
        reserve_price: u64,
        bid: Option<Bid>,
        history: TableVec<BidRecord>,
    }

    public struct AuctionManagerCap has key, store {
        id: UID,
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

    public fun new(
        name: String,
        starts_at_ts: u64,
        ends_at_ts: u64,
        reserve_price: u64,
        ctx: &mut TxContext,
    ): (Auction, AuctionManagerCap) {
        let opening_bid = Bid {
            bidder: ctx.sender(),
            timestamp: starts_at_ts,
            value: balance::zero(),
        };
        let auction = Auction {
            id: object::new(ctx),
            name: name,
            item_refs: vec_map::empty(),
            starts_at_ts: starts_at_ts,
            ends_at_ts: ends_at_ts,
            is_closed: false,
            reserve_price: reserve_price,
            bid: option::some(opening_bid),
            history: table_vec::empty(ctx),
        };
        let manager_cap = AuctionManagerCap {
            id: object::new(ctx),
            auction_id: object::id(&auction),
        };
        (auction, manager_cap)
    }

    public fun bid(
        auction: &mut Auction,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(auction.is_closed == false, EAuctionIsClosed);
        assert_auction_not_ended(auction, clock);
        assert_auction_not_started(auction, clock);

        // Extract the current bid from the Auction.
        let current_bid = auction.bid.extract();
        // Verify the value of the incoming bid is greater than the current bid value.
        assert!(payment.value() > current_bid.value.value(), 1);
        // Unwrap the current bid.
        let Bid {
            bidder,
            timestamp,
            value,
        } = current_bid;
        let record = BidRecord {
            bidder: bidder,
            timestamp: timestamp,
            value: value.value(),
        };
        // Add bid record to auction history.
        auction.history.push_back(record);
        // Transfer the extracted payment to the original bidder.
        transfer::public_transfer(coin::from_balance(value, ctx), bidder);

        // Create a new bid and put it into the auction.
        let new_bid = Bid {
            bidder: ctx.sender(),
            timestamp: clock.timestamp_ms(),
            value: payment.into_balance(),
        };
        auction.bid.fill(new_bid);
    }

    public fun close(
        cap: &AuctionManagerCap,
        auction: &mut Auction,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert_auction_manager_cap(cap, auction);

        let last_bid = auction.bid.extract();
        let Bid {
            bidder,
            timestamp: _,
            value,
        } = last_bid;

        let mut item_recipient = ctx.sender();
        if (value.value() > auction.reserve_price) {
            item_recipient = bidder;
        };

        while (!auction.item_refs.is_empty()) {
            let (item_id, item_typename) = auction.item_refs.remove_entry_by_idx(0);
            let claim_item_cap = ClaimItemCap {
                id: object::new(ctx),
                auction_id: object::id(auction),
                item_id: item_id,
                item_typename: item_typename,
            };
            transfer::public_transfer(claim_item_cap, item_recipient);
        };

        coin::from_balance(value, ctx)
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
            item_refs,
            starts_at_ts: _,
            ends_at_ts: _,
            is_closed: _,
            reserve_price: _,
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