import React, { useState } from 'react';
import { AnimeSearch } from './components/AnimeSearch';
import { AnimeSearchGrid } from './components/AnimeSearchGrid';
import { Recomendations } from './components/Recomendations';

export const RecAnime = () => {
    const [animeSearch, setAnimeSearch] = useState(['']);


    return (
        <>
            <h1> RecAnime </h1>
            <AnimeSearch setAnimeSearch={setAnimeSearch} />
            <hr />
            <ol>
                {
                        animeSearch.map(name =>
                            <AnimeSearchGrid
                                key={name}
                                name={name} />)
                }
            </ol>
            <h2>Animes Recomendados!</h2>
            <ol>
                {
                    <Recomendations />
                }
            </ol>

        </>
    );

}
