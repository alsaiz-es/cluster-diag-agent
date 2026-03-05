#!/usr/bin/env python3
import argparse, socket, threading
def handle(conn, addr):
    try:
        with conn:
            while True:
                data = conn.recv(4096)
                if not data: break
                conn.sendall(data)
    except Exception: pass
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--bind', default='0.0.0.0'); ap.add_argument('--port', type=int, default=9400)
    args=ap.parse_args()
    s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1)
    s.bind((args.bind,args.port)); s.listen(128)
    print(f"Echo server listening on {args.bind}:{args.port}", flush=True)
    try:
        while True:
            conn,addr=s.accept(); threading.Thread(target=handle, args=(conn,addr), daemon=True).start()
    except KeyboardInterrupt: pass
    finally: s.close()
if __name__=='__main__': main()
