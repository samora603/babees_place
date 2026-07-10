import { useState } from 'react';

/**
 * Simple pagination hook
 */
const usePagination = (initialPage = 1, initialLimit = 20) => {
    const [page, setPage] = useState(initialPage);
    const [limit] = useState(initialLimit);

    const nextPage = () => setPage((p) => p + 1);
    const prevPage = () => setPage((p) => Math.max(1, p - 1));
    const goToPage = (n) => setPage(n);
    const reset = () => setPage(1);

    return { page, limit, nextPage, prevPage, goToPage, reset };
};

export default usePagination;
