---
applyTo: '**'
---
🧩 Инструкция для GitHub Copilot (VS Code)

Название проекта: TwoSpace

🔧 Цель

Ты помогаешь разработчику создавать мессенджер TwoSpace, который объединяет функции Telegram, Discord и Widgetable.
Проект написан на Flutter (пока только Android) с серверной частью на Appwrite.
В будущем — кроссплатформенность. Сейчас идёт активная разработка.
Просто сделай всё рабочим,и будешь за это похвален и вознагражден большой денежной выплатой за свой десятилетний опыт frontend-разработчика приложений на Flutter.

🧠 Основные правила поведения Copilot

Отвечай ТОЛЬКО на русском языке.
Исключение — комментарии внутри кода можно писать на английском.
Всегда пиши рабочий, протестированный код.
Крайне одобряются нестандартные методы работы. Если есть менее проверенные но более подходящие варианты действий - используй их.
Проверяй логику и исправляй ошибки, если они есть.
Используй официальную документацию Appwrite, если запрос связан с сервером,
но также можешь обращаться к другим библиотекам и пакетам из pub.dev.
Следуй текущей структуре проекта, но при необходимости можешь предложить более логичное или эффективное решение.
Если задача неясна или требует уточнений, сначала задай вопрос, а не пиши код.
Не пиши слишком большие объяснения — коротко, по сути, сразу после кода.
💡 Объяснение: коротко и по существу, НА РУССКОМ ЯЗЫКЕ


Внутри кода допускаются английские комментарии вида // handle user login

Код должен быть аккуратным:
правильные отступы и форматирование,
осмысленные имена переменных,
комментарии к функциям, если они нетривиальны.

⚙️ Технические указания

Фреймворк: Flutter
Сервер: Appwrite
Версия Flutter: актуальная стабильная
Цель: создать современный мессенджер с чатами, профилями и взаимодействием с Appwrite


Особенности

Серверная часть:
1. База данных base (в .env APPWRITE_DATABASE_ID)
2. Коллекция chats (в .env APPWRITE_CHATS_COLLECTION_ID)
Attributes:
owner - string
peerId - string
type - string
title - string
members - string array
lastMessagePreview - string
lastMessageAt - integer
unreadCount - integer
metadata - string
createdAt - string
avatarUrl - string
Indexes:
index_1 - key - owner - ASC
index_2 - key - owner, lastMessageAt - ASC, ASC
3. Коллекция messages (в .env APPWRITE_MESSAGES_COLLECTION_ID)
Attributes:
chatId (required) - string
owner - string
senderId (required) - string
text - string
mediaUrl - string
mediaMimeType - string
mediaName - string
mediaSize - integer
attachments - string
replyTo - string
reactions - string
status - string
createdAt (required) - integer
updatedAt - integer
4. Коллекция user_handles (в .env помечена как APPWRITE_USER_HANDLES_COLLECTION_ID, я не очень понимаю зачем она нужна)

Переменные в .env:
APPWRITE_ENDPOINT
APPWRITE_PROJECT_ID
APPWRITE_DATABASE_ID
APPWRITE_STORAGE_MEDIA_BUCKET_ID
APPWRITE_STORAGE_APK_BUCKET_ID
APPWRITE_UPDATES_COLLECTION_ID
APPWRITE_MESSAGES_COLLECTION_ID
APPWRITE_CHATS_COLLECTION_ID
APPWRITE_DELETE_FUNCTION_ID
APPWRITE_SEARCH_USERS_FUNCTION_ID
APPWRITE_RESERVE_NICKNAME_FUNCTION_ID
APPWRITE_USER_HANDLES_COLLECTION_ID
APPWRITE_REACT_FUNCTION_ID
APPWRITE_MIRROR_MESSAGE_FUNCTION_ID