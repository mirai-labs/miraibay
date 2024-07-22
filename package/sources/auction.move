module miraibay::auction {
    
    use std::string::{String};
    use std::type_name::{Self, TypeName};
    use std::u64;

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

    public struct AUCTION has drop {}

    public struct Auction has key {
        id: UID,
        name: String,
        description: Option<String>,
        creator: address,
        duration: AuctionDuration,
        pricing: AuctionPricing,
        items: VecMap<ID, TypeName>,
        bid: Option<Bid>,
        history: TableVec<BidRecord>,
    }

    public struct AuctionDuration has store {
        start_ts: u64,
        end_ts: u64,
    }

    public struct AuctionPricing has store {
        min_bid_increment: u64,
        reserve_price: u64,
        starting_price: u64,
    }

    public struct AuctionManagerCap has key, store {
        id: UID,
        auction_id: ID,
    }

    public struct Bid has store {
        bidder: address,
        payment: Coin<SUI>,
        timestamp: u64,
    }

    public struct BidRecord has store {
        bidder: address,
        timestamp: u64,
        value: u64,
    }

    const EAuctionIsClosed: u64 = 1;
    const EAuctionNotStarted: u64 = 2;
    const EAuctionNotEnded: u64 = 3;
    const EInvalidAuctionManagerCap: u64 = 4;
    const EInvalidClaimItemCap: u64 = 5;

    public fun new(
        name: String,
        description: Option<String>,
        start_ts: u64,
        end_ts: u64,
        min_bid_increment: u64,
        reserve_price: u64,
        starting_price: u64,
        ctx: &mut TxContext,
    ): (Auction, AuctionManagerCap) {
        let duration = AuctionDuration {
            start_ts: start_ts,
            end_ts: end_ts,
        };

        let pricing = AuctionPricing {
            min_bid_increment: min_bid_increment,
            reserve_price: reserve_price,
            starting_price: starting_price,
        };
        
        let auction = Auction {
            id: object::new(ctx),
            name: name,
            description: description,
            creator: ctx.sender(),
            duration: duration,
            pricing: pricing,
            items: vec_map::empty(),
            bid: option::none(),
            history: table_vec::empty(ctx),
        };

        let auction_manager_cap = AuctionManagerCap {
            id: object::new(ctx),
            auction_id: object::id(&auction),
        };
        
        (auction, auction_manager_cap)
    }

    public fun bid(
        auction: &mut Auction,
        mut payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_auction_active(auction, clock);

        let target_bid_value: u64;
        if (auction.bid.is_none()) {
            target_bid_value = auction.pricing.starting_price;
            assert!(payment.value() >= target_bid_value, 1);
        } else {
            let prev_bid = auction.bid.extract();
            target_bid_value = prev_bid.payment.value() + auction.pricing.min_bid_increment;
            assert!(payment.value() >= target_bid_value, 1);
            let Bid {
                bidder,
                payment,
                timestamp: _,
            } = prev_bid;
            transfer::public_transfer(payment, bidder);
        };

        let refund_amount = payment.value() - target_bid_value;
        if (refund_amount > 0) {
            let coin_to_refund = payment.split(refund_amount, ctx);
            transfer::public_transfer(coin_to_refund, ctx.sender());
        };
    
        let bid = Bid {
            bidder: ctx.sender(),
            payment: payment,
            timestamp: clock.timestamp_ms(),
        };
        
        let bid_record = BidRecord {
            bidder: bid.bidder,
            timestamp: bid.timestamp,
            value: bid.payment.value(),
        };

        auction.bid.fill(bid);
        auction.history.push_back(bid_record);
    }

    public fun share(
        cap: &AuctionManagerCap,
        auction: Auction,
    ) {
        verify_auction_manager_cap(cap, &auction);
        transfer::share_object(auction) 
    }
    
    fun assert_auction_active(
        auction: &Auction,
        clock: &Clock,
    ) {
        assert!(clock.timestamp_ms() > auction.duration.start_ts, 1);
        assert!(clock.timestamp_ms() < auction.duration.end_ts, 2);
    }

    fun verify_auction_manager_cap(
        cap: &AuctionManagerCap,
        auction: &Auction,
    ) {
        assert!(cap.auction_id == object::id(auction), EInvalidAuctionManagerCap);
    }
}