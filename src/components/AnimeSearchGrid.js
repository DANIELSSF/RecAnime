import React from 'react';
import { useFetchAnimeSearch } from '../hooks/useFetchAnimeSearch';
import { AnimeSearchItem } from './AnimeSearchItem';


export const AnimeSearchGrid = ({ name }) => {
    const { data } = useFetchAnimeSearch(name);
    return (
        <>
            <h3>{name}</h3>
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