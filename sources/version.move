module sui_castle::version2 {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use std::string::{Self, String};
    use sui::event;

    // Error constants
    const E_INSUFFICIENT_CREDITS: u64 = 1;
    const E_ROUND_NOT_COMPLETED: u64 = 2;
    const E_INVALID_ROUND_ORDER: u64 = 3;

    // Game constants
    const HERO_PRICE: u64 = 100;

    // === Hot Potato Structs ===
    
    /// Represents an active game round that must be completed
    public struct RoundAction {
        round_number: u8,
        player: address,
        started_at: u64,
    }

    /// Represents pending certification that must be processed
    public struct PendingCertification {
        round_number: u8,
        player: address,
        points: u64,
    }

    // === Regular Game Objects ===

    public struct Hero has key, store {
        id: UID,
        owner: address,
        level: u64,
    }

    public struct PlayerAccount has key, store {
        id: UID,
        name: String,
        address_id: address,
        current_round: u8,
        credits: u64,
        points: u64,
    }

    // === Events ===

    public struct RoundStarted has copy, drop {
        player: address,
        round: u8,
        timestamp: u64,
    }

    public struct RoundCompleted has copy, drop {
        player: address,
        round: u8,
        points: u64,
        timestamp: u64,
    }

    // === Core Functions ===

    /// Starts a game round and returns a hot potato that must be completed
    public fun start_round(
        player_account: &mut PlayerAccount,
        round: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ): RoundAction {
        assert!(player_account.credits > 0, E_INSUFFICIENT_CREDITS);
        assert!(round == player_account.current_round + 1, E_INVALID_ROUND_ORDER);

        // Deduct credits
        player_account.credits = player_account.credits - 1;

        let action = RoundAction {
            round_number: round,
            player: tx_context::sender(ctx),
            started_at: clock::timestamp_ms(clock),
        };

        event::emit(RoundStarted {
            player: tx_context::sender(ctx),
            round: round,
            timestamp: clock::timestamp_ms(clock),
        });

        action
    }

    /// Completes a round and returns a certification potato that must be processed
    public fun complete_round(
        action: RoundAction,
        points: u64,
        ctx: &mut TxContext
    ): PendingCertification {
        let RoundAction { round_number, player, started_at: _ } = action;
        
        PendingCertification {
            round_number,
            player,
            points
        }
    }

    /// Processes the certification and updates player account
    public fun process_certification(
        player_account: &mut PlayerAccount,
        certification: PendingCertification,
        clock: &Clock,
    ) {
        let PendingCertification { round_number, player, points } = certification;
        
        // Update player state
        player_account.current_round = round_number;
        player_account.points = player_account.points + points;

        event::emit(RoundCompleted {
            player,
            round: round_number,
            points,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // Example usage in a PTB:
    // 1. start_round() -> RoundAction
    // 2. complete_round(RoundAction) -> PendingCertification
    // 3. process_certification(PendingCertification)
}