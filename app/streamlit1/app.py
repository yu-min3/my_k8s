# app.py
import streamlit as st

st.title("🌟 Streamlit + OAuth2 Proxy サンプル")
st.write("ログインに成功しました！")

name = st.text_input("あなたの名前は？")
if name:
    st.success(f"こんにちは、{name}さん！")
