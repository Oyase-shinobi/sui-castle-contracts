#[test_only]
module sui_castle::sui_castle_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use sui_castle::sui_castle::{Self, GameState, PlayerAccount};
    use std::string;
    use std::vector;

    const PLAYER1: address = @0xA1;
    const PLAYER2: address = @0xA2;
    
    fun setup_test(): Scenario {
        let mut scenario = test::begin(@0x1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, @0x1); {
            sui_castle::create_game_state(ctx(&mut scenario));
        };
        
        clock::share_for_testing(clock);
        scenario
    }

    #[test]
    fun test_leaderboard() {
        let mut scenario = setup_test();
        
        // Create accounts for both players
        next_tx(&mut scenario, PLAYER1); {
            let mut game_state = test::take_shared<GameState>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);
            
            sui_castle::create_account(
                &mut game_state,
                string::utf8(b"Player1"),
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(game_state);
            test::return_shared(clock);
        };

        next_tx(&mut scenario, PLAYER2); {
            let mut game_state = test::take_shared<GameState>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);
            
            sui_castle::create_account(
                &mut game_state,
                string::utf8(b"Player2"),
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(game_state);
            test::return_shared(clock);
        };

        // Check leaderboard
        next_tx(&mut scenario, PLAYER1); {
            let game_state = test::take_shared<GameState>(&scenario);
            let player_account = test::take_from_address<PlayerAccount>(&scenario, PLAYER1);
            let clock = test::take_shared<Clock>(&scenario);
            
            let leaderboard = sui_castle::get_top_players_by_points(
                &game_state,
                &player_account,
                &clock,
                ctx(&mut scenario)
            );
            
            // Verify leaderboard has 2 players
            assert!(vector::length(&leaderboard) == 2, 0);
            
            test::return_shared(game_state);
            test::return_to_address(PLAYER1, player_account);
            test::return_shared(clock);
        };
        
        test::end(scenario);
    }
}