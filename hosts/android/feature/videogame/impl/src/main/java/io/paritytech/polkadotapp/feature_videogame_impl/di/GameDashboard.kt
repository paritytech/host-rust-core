package io.paritytech.polkadotapp.feature_videogame_impl.di

import javax.inject.Qualifier

@Qualifier
@Retention(AnnotationRetention.BINARY)
internal annotation class GameDashboard

/** Placeholder host handed to Retrofit; rewritten per-request to the remote-config game dashboard URL. */
internal const val GAME_DASHBOARD_SENTINEL_HOST = "game-dashboard.sentinel"
internal const val GAME_DASHBOARD_SENTINEL_URL = "https://$GAME_DASHBOARD_SENTINEL_HOST/"
internal const val GAME_DASHBOARD_URL_KEY = "game_dashboard_url"
