module miraibay::auction {
    
    use std::string::{String};
    
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::table_vec::{Self, TableVec};

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

    public struct Auction<T: key + store> has key, store {
        id: UID,
        name: String,
        prize: Option<T>,
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

    const EAuctionIsPaused: u64 = 1;
    const EAuctionNotStarted: u64 = 2;
    const EAuctionNotEnded: u64 = 3;

    public fun new<T: key + store>(
        name: String,
        prize: T,
        starts_at_ts: u64,
        ends_at_ts: u64,
        reserve_price: u64,
        ctx: &mut TxContext,
    ): (Auction<T>, AuctionManagerCap) {
        let opening_bid = Bid {
            bidder: ctx.sender(),
            timestamp: starts_at_ts,
            value: balance::zero(),
        };
        let auction = Auction<T> {
            id: object::new(ctx),
            name: name,
            prize: option::some(prize),
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

    public fun bid<T: key + store>(
        auction: &mut Auction<T>,
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

    public fun close<T: key + store>(
        cap: &AuctionManagerCap,
        auction: &mut Auction<T>,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(cap.auction_id == object::id(auction), 1);

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
        
        transfer::public_transfer(auction.prize.extract(), prize_recipient);
        coin::from_balance(value, ctx)
    }

    public fun destroy_empty<T: key + store>(
        auction: Auction<T>,
    ) {
        let Auction {
            id,
            name: _,
            prize,
            starts_at_ts: _,
            ends_at_ts: _,
            is_closed: _,
            reserve_price: _,
            bid,
            history,
        } = auction;
        id.delete();
        prize.destroy_none();
        bid.destroy_none();
        history.destroy_empty();
    }
}