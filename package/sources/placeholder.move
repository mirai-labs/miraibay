module miraibay::placeholder {

    use std::string::{String};

    public struct Placeholder has key, store {
        id: UID,
        name: String,
        description: String,
        creator: address,
    }

    public fun new(
        name: String,
        description: String,
        ctx: &mut TxContext,
    ): Placeholder {
        let placeholder = Placeholder {
            id: object::new(ctx),
            name: name,
            description: description,
            creator: ctx.sender(),
        };
        placeholder
    }

    public fun drop(
        placeholder: Placeholder,
    ) {
        let Placeholder {
            id,
            name: _,
            description: _,
            creator: _,
        } = placeholder;
        id.delete();
    }
}  