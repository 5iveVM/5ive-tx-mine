use std::interfaces::spl_token;

account CampaignConfig {
    authority: pubkey;
    mint: pubkey;
    mint_authority: pubkey;
    start_slot: u64;
    slots_per_week: u64;
    total_weeks: u64;
    base_reward_atoms: u64;
    weekly_decay_bps: u64;
    token_decimals: u8;
    is_initialized: bool;
}

account UserMiningState {
    user_authority: pubkey;
    current_week: u64;
    last_increment_slot: u64;
    unclaimed_current_week_atoms: u64;
    claimed_total_atoms: u64;
    counted_tx_total: u64;
    is_initialized: bool;
}

pub total_weeks_default() -> u64 {
    return 26;
}

pub week1_reward_atoms_default() -> u64 {
    return 1000000000;
}

pub weekly_decay_bps_default() -> u64 {
    return 700;
}

pub token_decimals_default() -> u8 {
    return 9;
}

pub bps_denominator() -> u64 {
    return 10000;
}

pub decay_multiplier_bps(weekly_decay_bps: u64) -> u64 {
    return bps_denominator() - weekly_decay_bps;
}

fn now_slot() -> u64 {
    return get_clock().slot;
}

pub derive_campaign() -> (pubkey, u8) {
    return derive_pda("campaign");
}

pub derive_mint_authority(campaign: pubkey) -> (pubkey, u8) {
    return derive_pda("mint_authority", campaign);
}

pub derive_user_state(owner: pubkey) -> (pubkey, u8) {
    return derive_pda("user_state", owner);
}

pub current_week_index(campaign: CampaignConfig, current_slot: u64) -> u64 {
    if (current_slot <= campaign.start_slot) {
        return 0;
    }

    let elapsed = current_slot - campaign.start_slot;
    return elapsed / campaign.slots_per_week;
}

pub reward_for_week(base_reward_atoms: u64, weekly_decay_bps: u64, week: u64) -> u64 {
    let mut reward = base_reward_atoms;
    let mut i = 0;
    let multiplier = decay_multiplier_bps(weekly_decay_bps);

    while (i < week) {
        reward = (reward * multiplier) / bps_denominator();
        i = i + 1;
    }

    return reward;
}

pub initialize_campaign(
    campaign: CampaignConfig @mut @init(payer=authority, space=256, seeds=["campaign"]) @signer,
    authority: account @mut @signer,
    mint: spl_token::Mint @serializer("raw"),
    mint_authority: account @pda(seeds=["mint_authority", campaign]),
    slots_per_week: u64
) {
    require(slots_per_week > 0);
    require(!campaign.is_initialized);

    campaign.authority = authority.ctx.key;
    campaign.mint = mint.ctx.key;
    campaign.mint_authority = mint_authority.ctx.key;
    campaign.start_slot = now_slot();
    campaign.slots_per_week = slots_per_week;
    campaign.total_weeks = total_weeks_default();
    campaign.base_reward_atoms = week1_reward_atoms_default();
    campaign.weekly_decay_bps = weekly_decay_bps_default();
    campaign.token_decimals = token_decimals_default();
    campaign.is_initialized = true;
}

pub initialize_user_state(
    campaign: CampaignConfig @pda(seeds=["campaign"]),
    user_state: UserMiningState @mut @init(payer=user, space=256, seeds=["user_state", user.ctx.key]) @signer,
    user: account @mut @signer
) {
    require(campaign.is_initialized);
    require(!user_state.is_initialized);

    let week = current_week_index(campaign, now_slot());

    user_state.user_authority = user.ctx.key;
    user_state.current_week = week;
    user_state.last_increment_slot = 0;
    user_state.unclaimed_current_week_atoms = 0;
    user_state.claimed_total_atoms = 0;
    user_state.counted_tx_total = 0;
    user_state.is_initialized = true;
}

pub increment_usage(
    campaign: CampaignConfig @pda(seeds=["campaign"]),
    user_state: UserMiningState @mut @pda(seeds=["user_state", user.ctx.key]),
    user: account @signer
) {
    require(campaign.is_initialized);
    require(user_state.is_initialized);
    require(user_state.user_authority == user.ctx.key);

    let slot = now_slot();
    let week = current_week_index(campaign, slot);
    if (week > user_state.current_week) {
        user_state.current_week = week;
        user_state.unclaimed_current_week_atoms = 0;
    }

    // Campaign complete: sidecar is an intentional no-op.
    if (week >= campaign.total_weeks) {
        return;
    }

    // Only count one tx per slot per user.
    if (user_state.last_increment_slot == slot) {
        return;
    }

    let reward = reward_for_week(campaign.base_reward_atoms, campaign.weekly_decay_bps, week);
    user_state.unclaimed_current_week_atoms = user_state.unclaimed_current_week_atoms + reward;
    user_state.counted_tx_total = user_state.counted_tx_total + 1;
    user_state.last_increment_slot = slot;
}

pub claim_current_week(
    campaign: CampaignConfig @pda(seeds=["campaign"]),
    user_state: UserMiningState @mut @pda(seeds=["user_state", user.ctx.key]),
    user: account @signer,
    mint: spl_token::Mint @mut @serializer("raw"),
    destination: spl_token::TokenAccount @mut @serializer("raw"),
    mint_authority: account @pda(seeds=["mint_authority", campaign]),
    token_program: account
) {
    require(campaign.is_initialized);
    require(user_state.is_initialized);
    require(user_state.user_authority == user.ctx.key);
    require(campaign.mint == mint.ctx.key);
    require(campaign.mint_authority == mint_authority.ctx.key);

    let week = current_week_index(campaign, now_slot());
    if (week > user_state.current_week) {
        user_state.current_week = week;
        user_state.unclaimed_current_week_atoms = 0;
    }

    // No minting after schedule end (any stale amount already burned on rollover).
    if (week >= campaign.total_weeks) {
        return;
    }

    let amount = user_state.unclaimed_current_week_atoms;
    if (amount == 0) {
        return;
    }

    spl_token::SPLToken::mint_to(mint, destination, mint_authority, amount);
    user_state.claimed_total_atoms = user_state.claimed_total_atoms + amount;
    user_state.unclaimed_current_week_atoms = 0;
}
