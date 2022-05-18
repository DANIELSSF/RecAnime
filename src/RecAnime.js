import React from 'react';
import { Recomendations } from './components/Recomendations';

export const RecAnime = () => {

    return (
        <>
            <h1> RecAnime </h1>
            <hr />
            <h2>Animes Recomendados!</h2>
            <ol>
                {
                    <Recomendations />
                }
            </ol>

        </>
    );

}
