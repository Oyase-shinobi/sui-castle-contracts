module sui_castle::sui_castle {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::hash::keccak256;
    use sui::bcs;

    // === Errors ===
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_PLAYER_ACCOUNT_NOT_EXIST: u64 = 2;
    const E_ROUND_ALREADY_PLAYED: u64 = 3;
    const E_PREVIOUS_ROUND_NOT_CERTIFIED: u64 = 4;
    const E_ROUND_NOT_PLAYED: u64 = 5;
    const E_INSUFFICIENT_CREDITS: u64 = 6;
    const E_TREASURE_ALREADY_OPENED: u64 = 7;
    const E_TOO_EARLY_TO_CLAIM: u64 = 8;

    // === Constants ===
    const CLAIM_COOLDOWN: u64 = 86400000; // 24 hours in milliseconds

    // === Structs ===
    public struct GameAdmin has key {
        id: UID,
        admins: vector<address>
    }

    public struct PlayerAccount has key, store {
        id: UID,
        name: String,
        address_id: address,
        hero_owned: u64,
        round1_played: bool,
        round1_certified: bool,
        round2_played: bool,
        round2_certified: bool,
        round3_played: bool,
        round3_certified: bool,
        game_finished: bool,
        current_round: u8,
        round1_play_time: u64,
        round2_play_time: u64,
        round3_play_time: u64,
        round1_finish_time: u64,
        round2_finish_time: u64,
        round3_finish_time: u64,
        round1_treasure_opened: bool,
        round2_treasure_opened: bool,
        gold: u64,
        credits: u64,
        last_claim_time: u64,
        point: u64,
    }

    public struct GameState has key {
        id: UID,
        players: vector<address>,
    }

    public struct PlayerInfo has copy, drop {
        name: String,
        address_id: address,
        hero_owned: u64,
        current_round: u8,
        game_finished: bool,
        round1_play_time: u64,
        round2_play_time: u64,
        round3_play_time: u64,
        round1_finish_time: u64,
        round2_finish_time: u64,
        round3_finish_time: u64,
        last_claim_time: u64,
        point: u64,
    }

    public struct LeaderboardInfo has copy, drop {
        name: String,
        address_id: address,
        point: u64,
    }

    public struct PlayerCreated has copy, drop {
        player_address: address,
        name: String,
    }

    // === Init Function ===
    fun init(ctx: &mut TxContext) {
        let admin = GameAdmin {
            id: object::new(ctx),
            admins: vector[tx_context::sender(ctx)]
        };
        
        let game_state = GameState {
            id: object::new(ctx),
            players: vector::empty(),
        };

        transfer::share_object(game_state);
        transfer::transfer(admin, tx_context::sender(ctx));
    }

    // === Game Functions ===
    public entry fun create_account(
        game_state: &mut GameState,
        name: String,
        ctx: &mut TxContext
    ) {
        let player_address = tx_context::sender(ctx);
        let player_account = PlayerAccount {
            id: object::new(ctx),
            name,
            address_id: player_address,
            hero_owned: 1,
            gold: 0,
            round1_played: false,
            round1_certified: false,
            round2_played: false,
            round2_certified: false,
            round3_played: false,
            round3_certified: false,
            game_finished: false,
            current_round: 0,
            round1_play_time: 0,
            round2_play_time: 0,
            round3_play_time: 0,
            round1_finish_time: 0,
            round2_finish_time: 0,
            round3_finish_time: 0,
            round1_treasure_opened: false,
            round2_treasure_opened: false,
            credits: 1,
            last_claim_time: 0,
            point: 0,
        };

        vector::push_back(&mut game_state.players, player_address);
        transfer::transfer(player_account, player_address);
    }

    public entry fun play_round1(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.credits > 0, E_INSUFFICIENT_CREDITS);
        player_account.credits = player_account.credits - 1;
        player_account.round1_played = true;
        player_account.current_round = 1;
        player_account.round1_play_time = clock::timestamp_ms(clock);
    }

    public entry fun play_round2(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.credits > 0, E_INSUFFICIENT_CREDITS);
        assert!(player_account.round1_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        player_account.credits = player_account.credits - 1;
        player_account.round2_played = true;
        player_account.current_round = 2;
        player_account.round2_play_time = clock::timestamp_ms(clock);
    }

    public entry fun play_round3(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.credits > 0, E_INSUFFICIENT_CREDITS);
        assert!(player_account.round2_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        player_account.credits = player_account.credits - 1;
        player_account.round3_played = true;
        player_account.current_round = 3;
        player_account.round3_play_time = clock::timestamp_ms(clock);
    }

    public entry fun add_certificate_round1(
        admin: &GameAdmin,
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&admin.admins, &tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        assert!(player_account.round1_played, E_ROUND_NOT_PLAYED);
        player_account.round1_certified = true;
        player_account.round1_finish_time = clock::timestamp_ms(clock);
        player_account.point = player_account.point + points_earned;
    }

    public entry fun add_certificate_round2(
        admin: &GameAdmin,
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&admin.admins, &tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        assert!(player_account.round2_played, E_ROUND_NOT_PLAYED);
        player_account.round2_certified = true;
        player_account.round2_finish_time = clock::timestamp_ms(clock);
        player_account.point = player_account.point + points_earned;
    }

    public entry fun add_certificate_round3(
        admin: &GameAdmin,
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&admin.admins, &tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        assert!(player_account.round3_played, E_ROUND_NOT_PLAYED);
        player_account.round3_certified = true;
        player_account.round3_finish_time = clock::timestamp_ms(clock);
        player_account.game_finished = true;
        player_account.point = player_account.point + points_earned;
    }

    // Pseudo-random treasure opening functions
    public entry fun open_treasure_round1(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round1_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        assert!(!player_account.round1_treasure_opened, E_TREASURE_ALREADY_OPENED);
        
        let random_seed = generate_random_seed(clock, ctx);
        let random_gold = (random_seed % 10) + 1; // 1-10 gold
        
        player_account.gold = player_account.gold + random_gold;
        player_account.round1_treasure_opened = true;
    }

    public entry fun open_treasure_round2(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round2_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        assert!(!player_account.round2_treasure_opened, E_TREASURE_ALREADY_OPENED);
        
        let random_seed = generate_random_seed(clock, ctx);
        let random_gold = (random_seed % 11) + 5; // 5-15 gold
        
        player_account.gold = player_account.gold + random_gold;
        player_account.round2_treasure_opened = true;
    }

    public entry fun claim_credit(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        assert!(
            current_time - player_account.last_claim_time >= CLAIM_COOLDOWN,
            E_TOO_EARLY_TO_CLAIM
        );
        
        player_account.credits = player_account.credits + 3;
        player_account.last_claim_time = current_time;
    }

    public entry fun admin_add_credits(
        admin: &GameAdmin,
        player_account: &mut PlayerAccount,
        ctx: &mut TxContext
    ) {
        assert!(vector::contains(&admin.admins, &tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        player_account.credits = player_account.credits + 10;
    }

    // === View Functions ===
    public fun get_player_info(player_account: &PlayerAccount): PlayerInfo {
        PlayerInfo {
            name: player_account.name,
            address_id: player_account.address_id,
            hero_owned: player_account.hero_owned,
            current_round: player_account.current_round,
            game_finished: player_account.game_finished,
            round1_play_time: player_account.round1_play_time,
            round2_play_time: player_account.round2_play_time,
            round3_play_time: player_account.round3_play_time,
            round1_finish_time: player_account.round1_finish_time,
            round2_finish_time: player_account.round2_finish_time,
            round3_finish_time: player_account.round3_finish_time,
            last_claim_time: player_account.last_claim_time,
            point: player_account.point,
        }
    }

    // === Helper Functions ===
    fun generate_random_seed(clock: &Clock, ctx: &TxContext): u64 {
        let mut sender_bytes = bcs::to_bytes(&tx_context::sender(ctx));
        let time_bytes = bcs::to_bytes(&clock::timestamp_ms(clock));
        vector::append(&mut sender_bytes, time_bytes);
        let hash = keccak256(&sender_bytes);
        
        // Convert first 8 bytes to u64
        let mut value = 0u64;
        let mut i = 0u64;
        while (i < 8) {
            value = value << 8;
            value = value + (*vector::borrow(&hash, i as u64) as u64);
            i = i + 1;
        };
        value
    }


    public fun get_player_credit(player_account: &PlayerAccount): u64 {
        player_account.credits
    }

    public fun get_top_players_by_points(game_state: &GameState): vector<LeaderboardInfo> {
        let players = &game_state.players;
        let mut leaderboard = vector::empty<LeaderboardInfo>();
        let mut i = 0;
        let len = vector::length(players);
        
        while (i < len) {
            let player_address = *vector::borrow(players, i);
            let player_info = LeaderboardInfo {
                name: string::utf8(b""), // This will need to be updated with actual player name
                address_id: player_address,
                point: 0, // This will need to be updated with actual points
            };
            vector::push_back(&mut leaderboard, player_info);
            i = i + 1;
        };

        // Sort the leaderboard by points (descending order)
        sort_leaderboard(&mut leaderboard);
        leaderboard
    }

    // Helper function to sort the leaderboard
        fun sort_leaderboard(leaderboard: &mut vector<LeaderboardInfo>) {
        let len = vector::length(leaderboard);
        let mut i = 0;
        while (i < len) {
            let mut j = i + 1;
            while (j < len) {
                let player_i = vector::borrow(leaderboard, i);
                let player_j = vector::borrow(leaderboard, j);
                if (player_i.point < player_j.point) {
                    vector::swap(leaderboard, i, j);
                };
                j = j + 1;
            };
            i = i + 1;
        }
    }
}