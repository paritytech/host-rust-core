//! Prints canonical SCALE hex for each [`truapi_platform::UserConfirmationReview`]
//! sample, one `NAME=0x<hex>` line per sample, for host apps to pin as decoder
//! fixtures.

use truapi_platform::review_fixtures;

fn main() {
    for (name, review) in review_fixtures::all() {
        let hex = review_fixtures::encode_hex(&review);
        println!("{name}=0x{hex}");
    }
}
