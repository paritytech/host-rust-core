package io.paritytech.polkadotapp.feature_videogame_impl.data.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson

class AccountOrPersonData<T : Any>(val data: T, val key: OnChainAccountOrPerson) {
    companion object {
        fun <T : Any> fromAccount(data: T, accountId: AccountId): AccountOrPersonData<T> {
            return AccountOrPersonData(
                data = data,
                key = OnChainAccountOrPerson.Account(accountId)
            )
        }

        fun <T : Any> fromPerson(data: T, alias: PersonalAlias): AccountOrPersonData<T> {
            return AccountOrPersonData(
                data = data,
                key = OnChainAccountOrPerson.Person(alias)
            )
        }
    }
}

fun <T : Any, R : Any> AccountOrPersonData<T>.map(transform: (T) -> R): AccountOrPersonData<R> {
    return AccountOrPersonData(
        data = transform(data),
        key = key
    )
}
