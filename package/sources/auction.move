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

    public struct ClaimItemCap has key, store {
        id: UID,
        auction_id: ID,
        item_id: ID,
        item_typename: TypeName
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

    const MAX_ITEM_COUNT: u8 = 255;

    const EAuctionIsClosed: u64 = 1;
    const EAuctionNotStarted: u64 = 2;
    const EAuctionNotEnded: u64 = 3;
    const EInvalidAuctionManagerCap: u64 = 4;
    const EInvalidClaimItemCap: u64 = 5;

    fun init(
        otw: AUCTION,
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
    
    public fun new(
        name: String,
        description: Option<String>,
        start_ts: u64,
        end_ts: u64,
        min_bid_increment: u64,
        reserve_price: u64,
        starting_price: u64,
        ctx: &mut TxContext,
    ): AuctionManagerCap {
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
        
        transfer::share_object(auction);

        auction_manager_cap
    }

    public fun bid(
        auction: &mut Auction,
        mut payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_auction_active(auction, clock);

        // Assert payment is greater than or equal to starting price. This should always be the case.
        assert!(payment.value() >= auction.pricing.starting_price, 1);

        let mut target_bid_value = auction.pricing.starting_price;

        if (auction.bid.is_some()) {
            // Extract previous bid if it exists.
            let prev_bid = auction.bid.extract();
            // Overwrite target bid value with the minimum price of the current bid.
            target_bid_value = prev_bid.payment.value() + auction.pricing.min_bid_increment;
            // Assert the user's payment is bigly enough.
            assert!(payment.value() >= target_bid_value, 1);
            // Unwrap the Bid, and transfer previous bid's payment back to the associated bidder. 
            let Bid {
                bidder,
                payment,
                timestamp: _,
            } = prev_bid;
            transfer::public_transfer(payment, bidder);
        };

        // Determine whether 
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

    public fun add_item<T: key + store>(
        cap: &AuctionManagerCap,
        auction: &mut Auction,
        item: T,
        clock: &Clock,
    ) {
        verify_auction_manager_cap(cap, auction);
        assert_auction_active(auction, clock);
        assert!(auction.items.size() as u8 < MAX_ITEM_COUNT);
        auction.items.insert(object::id(&item), type_name::get<T>());
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
        auction.items.remove(&object::id(&item));
        transfer::public_transfer(item, ctx.sender());
        
        let ClaimItemCap {
            id,
            auction_id: _,
            item_id: _,
            item_typename: _,
        } = cap;
        id.delete();
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