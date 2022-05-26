import React from 'react'

export const AnimeSearchItem = ({ id, url, title, synopsis, source, episodes, status, score, year }) => {

    return (
        <>
            <div className='cardSearch animate__animated animate__zoomIn '>
                <div className='container-sm'>
                    <p><strong>{title}</strong></p>
                    <p>Year:{year} | Episodes:{episodes}  Status:{status}</p>
                    <img src={url} alt={title}></img> <p>Synopsis:{synopsis}</p>
                    <p>Score:{score} | Source:{source}</p>
                </div>
            </div>
        </>
    )

}