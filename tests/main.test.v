// Deterministic reward and rollover checks.

// @test-params 1000000000 1000000000
pub test_week0_reward(base_reward_atoms: u64) -> u64 {
    return base_reward_atoms;
}

// @test-params 1000000000 930000000
pub test_week1_reward(base_reward_atoms: u64) -> u64 {
    return (base_reward_atoms * 9300) / 10000;
}

// @test-params 1000000000 864900000
pub test_week2_reward(base_reward_atoms: u64) -> u64 {
    let week1 = (base_reward_atoms * 9300) / 10000;
    return (week1 * 9300) / 10000;
}

// @test-params 930000000 3 4 0
pub test_rollover_burns_unclaimed(unclaimed: u64, old_week: u64, new_week: u64) -> u64 {
    if (new_week > old_week) {
        return 0;
    }
    return unclaimed;
}

// @test-params 930000000 4 4 930000000
pub test_same_week_keeps_unclaimed(unclaimed: u64, old_week: u64, new_week: u64) -> u64 {
    if (new_week > old_week) {
        return 0;
    }
    return unclaimed;
}

// @test-params 26 26 true
pub test_campaign_end_no_mint(current_week: u64, total_weeks: u64) -> bool {
    return current_week >= total_weeks;
}
