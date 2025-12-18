import { supabase } from '@/integrations/supabase/client';

export const TMDB_BASE_URL = 'https://api.themoviedb.org/3';
export const TMDB_IMAGE_BASE_URL = 'https://image.tmdb.org/t/p/w500';

export interface TMDBContent {
    id: number;
    title?: string;
    name?: string;
    vote_average: number;
    release_date?: string;
    first_air_date?: string;
    poster_path: string | null;
    backdrop_path: string | null;
    overview: string;
    original_language: string;
    genre_ids?: number[];
}

// Fetch from TMDB via edge function proxy
const fetchFromProxy = async (path: string, params: string = ''): Promise<any> => {
    try {
        const { data, error } = await supabase.functions.invoke('tmdb-proxy', {
            body: { path, params }
        });

        if (error) {
            console.error('TMDB proxy error:', error);
            return null;
        }

        return data;
    } catch (error) {
        console.error('Error calling TMDB proxy:', error);
        return null;
    }
};

export const fetchByPath = async (path: string, params: string = ''): Promise<TMDBContent[]> => {
    try {
        const data = await fetchFromProxy(path, params);
        return data?.results || [];
    } catch (error) {
        console.error(`Error fetching ${path}:`, error);
        return [];
    }
};

export const fetchContent = async (type: 'movie' | 'tv' | 'short', language?: string): Promise<TMDBContent[]> => {
    const langParam = language && language !== 'all' ? `&with_original_language=${language}` : '';

    if (type === 'tv') {
        return fetchByPath('/discover/tv', `&sort_by=popularity.desc&include_adult=false&include_null_first_air_dates=false&page=1${langParam}`);
    } else if (type === 'short') {
        return fetchByPath('/discover/movie', `&sort_by=popularity.desc&include_adult=false&include_video=false&page=1&with_runtime.lte=40${langParam}`);
    } else {
        if (language && language !== 'all') {
            return fetchByPath('/discover/movie', `&sort_by=popularity.desc&include_adult=false&include_video=false&page=1${langParam}`);
        } else {
            return fetchByPath('/movie/now_playing', `&page=1&region=IN`);
        }
    }
};

export const fetchTrending = (type: 'movie' | 'tv' = 'movie') => fetchByPath(`/trending/${type}/week`);
export const fetchTopRated = (type: 'movie' | 'tv' = 'movie') => fetchByPath(`/${type}/top_rated`, '&page=1');
export const fetchUpcoming = () => fetchByPath('/movie/upcoming', '&page=1&region=IN');
export const fetchActionMovies = () => fetchByPath('/discover/movie', '&with_genres=28&sort_by=popularity.desc');
export const fetchComedyMovies = () => fetchByPath('/discover/movie', '&with_genres=35&sort_by=popularity.desc');
export const fetchIndianMovies = () => fetchByPath('/discover/movie', '&with_original_language=hi|te|ta|ml|kn&sort_by=popularity.desc&region=IN');

// Fetch detailed information for a specific movie or TV show
export const fetchContentDetails = async (id: number, type: 'movie' | 'tv' = 'movie') => {
    try {
        const endpoint = type === 'movie' ? `/movie/${id}` : `/tv/${id}`;
        const data = await fetchFromProxy(endpoint, '&append_to_response=credits,videos,similar,reviews');
        return data;
    } catch (error) {
        console.error(`Error fetching ${type} details:`, error);
        return null;
    }
};

// Alias for backward compatibility
export const fetchLatestRatings = () => fetchContent('movie');
export const fetchMovies = (language?: string) => fetchContent('movie', language);
