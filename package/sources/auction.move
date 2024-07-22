module miraibay::auction {
    
    use std::string::{String};
    use std::type_name::{Self, TypeName};
    
    use sui::object_bag::{Self, ObjectBag};
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::table_vec::{Self, TableVec};
    use sui::vec_map::{Self, VecMap};

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

    public struct Auction has key, store {
        id: UID,
        name: String,
        prizes: VecMap<ID, TypeName>,
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

    public struct ClaimPrizeCap has key, store {
        id: UID,
        auction_id: ID,
        prize_id: ID,
        prize_typename: TypeName
    }

    const EAuctionIsPaused: u64 = 1;
    const EAuctionNotStarted: u64 = 2;
    const EAuctionNotEnded: u64 = 3;
    const EInvalidAuctionManagerCap: u64 = 4;
    const EInvalidClaimPrizeCap: u64 = 5;

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
            prizes: vec_map::empty(),
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
        assert!(auction.is_closed == false, EAuctionIsPaused);
        assert!(clock.timestamp_ms() > auction.starts_at_ts, EAuctionNotStarted);
        assert!(clock.timestamp_ms() < auction.ends_at_ts, EAuctionNotEnded);

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
        verify_auction_manager_cap(cap, auction);

        let last_bid = auction.bid.extract();
        let Bid {
            bidder,
            timestamp: _,
            value,
        } = last_bid;

        let mut prize_recipient = ctx.sender();
        if (value.value() > auction.reserve_price) {
            prize_recipient = bidder;
        };

        while (!auction.prizes.is_empty()) {
            let (prize_id, prize_typename) = auction.prizes.remove_entry_by_idx(0);
            let claim_prize_cap = ClaimPrizeCap {
                id: object::new(ctx),
                auction_id: object::id(auction),
                prize_id: prize_id,
                prize_typename: prize_typename,
            };
            transfer::public_transfer(claim_prize_cap, prize_recipient);
        };

        coin::from_balance(value, ctx)
    }

    public fun add_prize<T: key + store>(
        cap: &AuctionManagerCap,
        auction: &mut Auction,
        prize: T,
    ) {
        verify_auction_manager_cap(cap, auction);
        auction.prizes.insert(object::id(&prize), type_name::get<T>());
        transfer::public_transfer(prize, auction.id.to_address());
    }

    public fun claim_prize<T: key + store>(
        cap: ClaimPrizeCap,
        auction: &mut Auction,
        prize: T,
        ctx: &mut TxContext,
    ) {
        assert!(cap.auction_id == object::id(auction), EInvalidClaimPrizeCap);
        assert!(cap.prize_id == object::id(&prize), EInvalidClaimPrizeCap);
        assert!(cap.prize_typename == type_name::get<T>(), EInvalidClaimPrizeCap);

        auction.prizes.remove(&object::id(&prize));
        
        let ClaimPrizeCap {
            id,
            auction_id: _,
            prize_id: _,
            prize_typename: _,
        } = cap;
        id.delete();

        transfer::public_transfer(prize, ctx.sender());
    }

    public fun destroy_empty(
        auction: Auction,
    ) {
        let Auction {
            id,
            name: _,
            prizes,
            starts_at_ts: _,
            ends_at_ts: _,
            is_closed: _,
            reserve_price: _,
            bid,
            history,
        } = auction;
        id.delete();
        prizes.destroy_empty();
        bid.destroy_none();
        history.destroy_empty();
    }

    fun verify_auction_manager_cap(
        cap: &AuctionManagerCap,
        auction: &Auction,
    ) {
        assert!(cap.auction_id == object::id(auction), EInvalidAuctionManagerCap);
    }
}