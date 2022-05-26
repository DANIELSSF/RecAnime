import React, { useState } from 'react'
import PropTypes from 'prop-types'

export const AnimeSearch = ({ setAnimeSearch }) => {
    const [inputAnimeSearch, setInputAnimeSearch] = useState('');

    const handleSearchAnime = (e) => {
        setInputAnimeSearch(e.target.value);
    }
    const handleSubmitAnime = (e) => {
        e.preventDefault();

        if (inputAnimeSearch.trim().length > 2) {

            setAnimeSearch({ data: inputAnimeSearch, state: true });
            setInputAnimeSearch('');
        }

    }
    return (
        <>
            <form onSubmit={handleSubmitAnime}>

                <input
                    className='form-control'
                    placeholder='Buscar Anime...'

                    type='text'
                    value={inputAnimeSearch}
                    onChange={handleSearchAnime}>

                </input>
            </form>
        </>
    )

}
AnimeSearch.propTypes = {
    setAnimeSearch: PropTypes.func.isRequired
}