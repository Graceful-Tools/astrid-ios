//! `core/deny.toml` is astrid-core's generated copy for this repository, byte for byte (AITD-665,
//! astrid-core task 32d7c04d).
//!
//! The four `deny.toml` files used to be hand copies, and they drifted: on 2026-11-14 astrid-core
//! allowed `BSD-2-Clause` and `MPL-2.0` and the other three did not know. astrid-core now renders
//! each consumer's copy (`cargo xtask gen-deny`) and carries it in `astrid_core::supply_chain`, so
//! this checks the copy against the core THIS REPOSITORY PINS, offline, and the answer changes
//! only when the pin does. To update `core/deny.toml`, bump the pin and copy
//! `supply-chain/deny.astrid-ios.toml` from that revision.

#[test]
fn deny_toml_is_the_core_it_pins_aitd665() {
    // Without this, a repository key the core does not know would make `matches` false — and a
    // future helper that answered "nothing to compare" with true would pass for ever.
    assert!(
        astrid_core::supply_chain::deny_toml("astrid-ios").is_some(),
        "the pinned astrid-core generates no deny.toml for astrid-ios"
    );

    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../deny.toml");
    let committed = std::fs::read_to_string(path).expect("core/deny.toml is readable");
    assert!(
        astrid_core::supply_chain::matches("astrid-ios", &committed),
        "core/deny.toml is not the copy the pinned astrid-core generated for astrid-ios; copy \
         supply-chain/deny.astrid-ios.toml from the pinned revision"
    );
}
