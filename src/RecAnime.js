import React, { useState } from 'react';
import { AnimeSearch } from './components/AnimeSearch';
import { AnimeSearchGrid } from './components/AnimeSearchGrid';
import { Recomendations } from './components/Recomendations';

export const RecAnime = () => {
    const [animeSearch, setAnimeSearch] = useState({ data: '', state: false });
    const { data, state } = animeSearch;


    return (
        <>
            <div className='container-sm'>
                <h1 ><strong> RecAnime </strong></h1>
                <AnimeSearch setAnimeSearch={setAnimeSearch} />
                <hr />
                <ol>
                    {
                        state &&
                        <AnimeSearchGrid
                            name={data} />
                    }

                </ol>
                <h2>Animes Recomendados!</h2>
                <ol>
                    {
                        <Recomendations />
                    }
                </ol>
            </div>
        </>
    );

}
