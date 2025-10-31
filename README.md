# 🎵 LastFM API Testing

A lightweight Swift project for experimenting with the [Last.fm API](https://www.last.fm/api).  
This repo is intended as a sandbox for testing requests, parsing responses, and learning how to work with external APIs in Swift.

---

## 🚀 Overview

This project demonstrates:
- How to make API calls to the Last.fm web service.
- Parsing and decoding JSON responses into Swift models.
- Setting up simple test cases for API interactions.
- A foundation for expanding into a full-featured Last.fm client.

---

## 🧰 Project Structure

| Path | Description |
|------|--------------|
| `Last.fmAPI.xcodeproj` | The main Xcode project file |
| `Last.fmAPI/` | Source files for the app |
| `Last.fmAPITests/` | Unit tests for API calls and logic |
| `Last.fmAPIUITests/` | UI test targets |
| `Last-fmAPI-Info.plist` | App configuration and environment settings |
| `.gitignore` | Ignored build and system files |

---

## ✅ Current Features

- Simple GET requests to Last.fm API endpoints  
- JSON decoding using Swift’s `Codable`  
- Example methods for artist info, tracks, and more  
- Basic unit tests for key functions  

---

## ⚠️ Limitations

- Not a production app — this is a **testing environment**  
- Minimal UI (mostly console output and testing)  
- Only a few API endpoints implemented  
- No rate-limiting, caching, or error recovery mechanisms yet  

---

## 🧩 Requirements

- macOS with **Xcode** (latest version recommended)
- A **Last.fm API Key** — [get one here](https://www.last.fm/api/account/create)

---
   git clone https://github.com/danepainter/LastFM-api-testing.git
   cd LastFM-api-testing
