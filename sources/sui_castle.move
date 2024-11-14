module sui_castle::sui_castle {
    /*
        SUI Castle is a blockchain game where players can:
        - Create an account and receive an initial hero
        - Play through 3 rounds of challenges
        - Earn points, gold and credits by completing rounds
        - Open treasure chests after completing rounds
        - Buy additional heroes with gold
        - Compete on the leaderboard based on points earned
        
        Key features:
        - Each round requires 1 credit to play
        - Players must complete and certify previous round before advancing
        - Daily cooldown on claiming free credits and gold
        - Pseudo-random rewards from treasure chests and gold claims using clock and tx hash
        - Top 10 players shown on leaderboard
        
        Note: True randomness is not possible on-chain. The game uses pseudo-random 
        number generation based on transaction hash and timestamp for gameplay mechanics.
        This is not cryptographically secure and should not be used for high-value
        randomization needs.
    */

    // >>>>>> Imports <<<<<<
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::hash::keccak256;
    use sui::bcs;
    use sui::event;
    use sui::random::{Self, Random, RandomGenerator};
    // >>>>>> Imports <<<<<<
    
    // >>>>>> Errors <<<<<<
    const E_PLAYER_ACCOUNT_NOT_EXIST: u64 = 2;
    const E_ROUND_ALREADY_PLAYED: u64 = 3;
    const E_PREVIOUS_ROUND_NOT_CERTIFIED: u64 = 4;
    const E_ROUND_NOT_PLAYED: u64 = 5;
    const E_INSUFFICIENT_CREDITS: u64 = 6;
    const E_TREASURE_ALREADY_OPENED: u64 = 7;
    const E_TOO_EARLY_TO_CLAIM: u64 = 8;
    const E_INSUFFICIENT_GOLD: u64 = 9;
    const HERO_PRICE: u64 = 100;
    const CLAIM_COOLDOWN: u64 = 86400000;
    // >>>>>> Errors <<<<<<

    // >>>>>> Objects <<<<<<
    public struct GameState has key {
        id: UID,
        players: vector<address>,
    }
    // >>>>>> Objects <<<<<<
    
    // >>>>>> Structs <<<<<<
    public struct Hero has key, store {
        id: UID,
        owner: address,
        level: u64,
        created_at: u64,
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
    // >>>>>> Structs <<<<<<

    // >>>>>> Events <<<<<<
    public struct PlayerInfoQueried has copy, drop {
        player_address: address,
        name: String,
        hero_owned: u64,
        current_round: u8,
        timestamp: u64,
    }

    public struct HeroMinted has copy, drop {
        hero_id: ID,
        owner: address,
        created_at: u64,
    }

    public struct PlayerCreditQueried has copy, drop {
        player_address: address,
        credits: u64,
        timestamp: u64,
    }

    public struct LeaderboardQueried has copy, drop {
        queried_by: address,
        timestamp: u64,
        top_player: address,
        top_score: u64,
    }

    public struct LeaderboardInfo has copy, drop {
        pub name: String,
        pub address_id: address,
        pub point: u64,
    }

    public struct PlayerCreated has copy, drop {
        player_address: address,
        name: String,
    }

    public struct TreasureOpened has copy, drop {
        player_address: address,
        gold_earned: u64,
        timestamp: u64,
    }

    public struct CreditsGranted has copy, drop {
        player_address: address,
        credits_amount: u64,
        timestamp: u64,
    }

    public struct GoldGranted has copy, drop {
        player_address: address,
        gold_amount: u64,
        timestamp: u64,
    }
    // >>>>>> Events <<<<<<

    // >>>>>> Initialization <<<<<<
    fun init(ctx: &mut TxContext) {
        let game_state = GameState {
            id: object::new(ctx),
            players: vector::empty(),
        };
        transfer::share_object(game_state);
    }
    // >>>>>> Initialization <<<<<<

    // >>>>>> Entry Functions <<<<<<
    public entry fun create_account(
        game_state: &mut GameState,
        name: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let player_address = tx_context::sender(ctx);
        
        let initial_hero = Hero {
            id: object::new(ctx),
            owner: player_address,
            level: 1,
            created_at: clock::timestamp_ms(clock),
        };

        let player_account = PlayerAccount {
            id: object::new(ctx),
            name,
            address_id: player_address,
            hero_owned: 1,
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
            gold: 0,
            credits: 1,
            last_claim_time: 0,
            point: 0,
        };

        event::emit(HeroMinted {
            hero_id: object::uid_to_inner(&initial_hero.id),
            owner: player_address,
            created_at: clock::timestamp_ms(clock),
        });

        vector::push_back(&mut game_state.players, player_address);
        transfer::transfer(initial_hero, player_address);
        transfer::transfer(player_account, player_address);
    }

    public entry fun buy_hero(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.gold >= HERO_PRICE, E_INSUFFICIENT_GOLD);
        player_account.gold = player_account.gold - HERO_PRICE;
        
        let hero = Hero {
            id: object::new(ctx),
            owner: player_account.address_id,
            level: 1,
            created_at: clock::timestamp_ms(clock),
        };

        player_account.hero_owned = player_account.hero_owned + 1;

        event::emit(HeroMinted {
            hero_id: object::uid_to_inner(&hero.id),
            owner: player_account.address_id,
            created_at: clock::timestamp_ms(clock),
        });

        transfer::transfer(hero, player_account.address_id);
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
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round1_played, E_ROUND_NOT_PLAYED);
        player_account.round1_certified = true;
        player_account.round1_finish_time = clock::timestamp_ms(clock);
        player_account.point = player_account.point + points_earned;
    }

    public entry fun add_certificate_round2(
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round2_played, E_ROUND_NOT_PLAYED);
        player_account.round2_certified = true;
        player_account.round2_finish_time = clock::timestamp_ms(clock);
        player_account.point = player_account.point + points_earned;
    }

    public entry fun add_certificate_round3(
        player_account: &mut PlayerAccount,
        points_earned: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round3_played, E_ROUND_NOT_PLAYED);
        player_account.round3_certified = true;
        player_account.round3_finish_time = clock::timestamp_ms(clock);
        player_account.game_finished = true;
        player_account.point = player_account.point + points_earned;
    }

    public entry fun open_treasure_round1(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round1_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        
        let random_seed = generate_random_seed(clock, ctx);
        let random_gold = (random_seed % 10) + 1;
        
        player_account.gold = player_account.gold + random_gold;

        event::emit(TreasureOpened {
            player_address: player_account.address_id,
            gold_earned: random_gold,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    public entry fun open_treasure_round2(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(player_account.round2_certified, E_PREVIOUS_ROUND_NOT_CERTIFIED);
        
        let random_seed = generate_random_seed(clock, ctx);
        let random_gold = (random_seed % 11) + 5;
        
        player_account.gold = player_account.gold + random_gold;

        event::emit(TreasureOpened {
            player_address: player_account.address_id,
            gold_earned: random_gold,
            timestamp: clock::timestamp_ms(clock),
        });
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

    public entry fun claim_100_credits(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        assert!(
            current_time - player_account.last_claim_time >= CLAIM_COOLDOWN,
            E_TOO_EARLY_TO_CLAIM
        );
        
        player_account.credits = player_account.credits + 100;
        player_account.last_claim_time = current_time;

        event::emit(CreditsGranted {
            player_address: player_account.address_id,
            credits_amount: 100,
            timestamp: current_time,
        });
    }

    public entry fun claim_gold(
        player_account: &mut PlayerAccount,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        assert!(
            current_time - player_account.last_claim_time >= CLAIM_COOLDOWN,
            E_TOO_EARLY_TO_CLAIM
        );
        
        let random_seed = generate_random_seed(clock, ctx);
        let random_gold = (random_seed % 5) + 1;
        
        player_account.gold = player_account.gold + random_gold;
        player_account.last_claim_time = current_time;

        event::emit(GoldGranted {
            player_address: player_account.address_id,
            gold_amount: random_gold,
            timestamp: current_time,
        });
    }
    // >>>>>> Entry Functions <<<<<<

    // >>>>>> Get Functions <<<<<<
    public fun get_player_info(
        player_account: &PlayerAccount,
        clock: &Clock,
        ctx: &TxContext
    ): PlayerInfo {
        let info = PlayerInfo {
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
        };

        event::emit(PlayerInfoQueried {
            player_address: player_account.address_id,
            name: player_account.name,
            hero_owned: player_account.hero_owned,
            current_round: player_account.current_round,
            timestamp: clock::timestamp_ms(clock),
        });

        info
    }

    public fun get_player_credit(
        player_account: &PlayerAccount,
        clock: &Clock,
        ctx: &TxContext
    ): u64 {
        event::emit(PlayerCreditQueried {
            player_address: player_account.address_id,
            credits: player_account.credits,
            timestamp: clock::timestamp_ms(clock),
        });

        player_account.credits
    }

    public fun get_top_players_by_points(
        game_state: &GameState,
        player_accounts: &vector<PlayerAccount>,
        clock: &Clock,
        ctx: &TxContext
    ): vector<LeaderboardInfo> {
        let players = &game_state.players;
        let mut leaderboard = vector::empty<LeaderboardInfo>();
        let mut i = 0;
        let len = vector::length(players);
        
        while (i < len) {
            let player_address = *vector::borrow(players, i);
            let player_account = vector::borrow(player_accounts, i);
            
            let player_info = LeaderboardInfo {
                name: player_account.name,
                address_id: player_address,
                point: player_account.point,
            };
            vector::push_back(&mut leaderboard, player_info);
            i = i + 1;
        };

        sort_leaderboard(&mut leaderboard);

        if (vector::length(&leaderboard) > 0) {
            let mut i = 0;
            let len = if (vector::length(&leaderboard) > 10) 10 else vector::length(&leaderboard);
            
            while (i < len) {
                let player = vector::borrow(&leaderboard, i);
                event::emit(*player);  
                i = i + 1;
            }
        };

        leaderboard
    }

    public fun get_top_players_by_points_2(
        game_state: &GameState,
        clock: &Clock,
        ctx: &TxContext
    ): vector<LeaderboardInfo> {
        let players = &game_state.players;
        let mut leaderboard = vector::empty<LeaderboardInfo>();
        let mut i = 0;
        let len = vector::length(players);
        
        while (i < len) {
            let player_address = *vector::borrow(players, i);
            if (let Some(player_info) = get_player_info(player_address)) {
                vector::push_back(&mut leaderboard, player_info);
            };
            i = i + 1;
        };

        sort_leaderboard(&mut leaderboard);
        leaderboard
    }
    // >>>>>> Get Functions <<<<<<
    
    // >>>>>> Helper Functions <<<<<<
    
    fun generate_random_seed(r: &Random, ctx: &mut TxContext): u64 {
        let mut generator = random::new_generator(r, ctx);
        random::generate_u64(&mut generator)
    }

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
    // >>>>>> Helper Functions <<<<<<
}
