import React from 'react';
import { useFetchAnimeSearch } from '../hooks/useFetchAnimeSearch';
import { AnimeSearchItem } from './AnimeSearchItem';
import PropTypes from 'prop-types';

export const AnimeSearchGrid = ({ name }) => {

    const { data } = useFetchAnimeSearch(name);

    return (
        <>
            <h3 className='card-grid animate__animated animate__bounce'>Anime: {name}</h3>
            <div>
                {
                    data.map(anime => (
                        <AnimeSearchItem
                            key={anime.id}
                            {...anime} />
                    ))
                }
            </div>
        </>
    )

}

AnimeSearchGrid.propTypes = {
    name: PropTypes.string.isRequired
}