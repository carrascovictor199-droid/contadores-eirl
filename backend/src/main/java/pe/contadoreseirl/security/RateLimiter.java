package pe.contadoreseirl.security;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/** Límite de intentos en memoria (ventana deslizante). Suficiente para una sola instancia del backend. */
@Component
public class RateLimiter {
    private final Map<String, Deque<Long>> golpes = new ConcurrentHashMap<>();

    /** true si la petición está permitida; false si superó "max" intentos dentro de la ventana. */
    public boolean permitir(String clave, int max, long ventanaMs) {
        long ahora = System.currentTimeMillis();
        if (golpes.size() > 10_000) limpiar(ahora, ventanaMs);
        Deque<Long> q = golpes.computeIfAbsent(clave, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && ahora - q.peekFirst() > ventanaMs) q.pollFirst();
            if (q.size() >= max) return false;
            q.addLast(ahora);
            return true;
        }
    }

    private void limpiar(long ahora, long ventanaMs) {
        golpes.entrySet().removeIf(e -> {
            synchronized (e.getValue()) {
                return e.getValue().isEmpty() || ahora - e.getValue().peekLast() > ventanaMs;
            }
        });
    }
}
