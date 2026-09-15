package io.paritytech.polkadotapp.feature_people_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId.Companion.intoPersonId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface PersonIdStorage {
    fun savePersonId(personId: PersonId)
    fun getPersonId(): PersonId?
    fun subscribePersonId(): Flow<PersonId?>
}

private const val PERSON_ID_KEY = "PersonId.Key"
private const val PERSON_ID_DEFAULT = -1L

class RealPersonIdStorage @Inject constructor(
    private val preferences: Preferences
) : PersonIdStorage {
    override fun savePersonId(personId: PersonId) {
        preferences.putLong(PERSON_ID_KEY, personId.id.toLong())
    }

    override fun getPersonId(): PersonId? {
        val longValue = preferences.getLong(PERSON_ID_KEY, PERSON_ID_DEFAULT)
        return longValue.mapToPersonIdOrNull()
    }

    override fun subscribePersonId(): Flow<PersonId?> {
        return preferences.longFlow(PERSON_ID_KEY, PERSON_ID_DEFAULT).map {
            it.mapToPersonIdOrNull()
        }
    }

    private fun Long.mapToPersonIdOrNull(): PersonId? = if (this == PERSON_ID_DEFAULT)
        null
    else
        toBigInteger().intoPersonId()
}
