import streamlit as st
import yfinance as yf
import pandas as pd
from datetime import datetime
from dateutil.relativedelta import relativedelta

# 1. 자산 유니버스 정의
ASSET_UNIVERSE = {
    '공격자산': ['SPY', 'EFA'],
    '안전자산': ['SHY', 'IEF', 'TLT', 'TIP', 'LQD', 'HYG', 'BNDX', 'EMB'],
    '현금': 'CASH'
}

# 2. 데이터 가져오는 함수
@st.cache_data
def get_historical_data(tickers, months=13):
    # 오늘 날짜 기준으로 시작일 계산 (최근 1년치 수익률 + 6개월 수익률 계산을 위해 여유 있게 가져옴)
    end_date = datetime.today()
    start_date = end_date - relativedelta(months=months)
    
    data = yf.download(tickers, start=start_date.strftime('%Y-%m-%d'), end=end_date.strftime('%Y-%m-%d'))['Adj Close']
    
    # 월말 데이터만 추출
    monthly_data = data.resample('M').last()
    return monthly_data

# 3. 모멘텀 계산 함수
def calculate_momentum(data, months):
    if len(data) < months + 1:
        return None
    
    current_price = data.iloc[-1]
    past_price = data.iloc[-(months + 1)]
    
    momentum = (current_price / past_price) - 1
    return momentum

# 4. 전략 실행 함수
def run_modified_dual_momentum():
    all_tickers = ASSET_UNIVERSE['공격자산'] + ASSET_UNIVERSE['안전자산']
    data = get_historical_data(all_tickers)
    
    if data is None or data.empty:
        return {"error": "데이터를 불러오지 못했습니다."}

    # 현재 SPY의 1년 수익률 확인
    spy_1yr_mom = calculate_momentum(data[['SPY']], 12)
    
    if spy_1yr_mom is None:
         return {"error": "SPY의 1년 데이터가 충분하지 않습니다."}

    result = {}
    
    # 공격자산 모드: SPY 1년 수익률 > 0
    if spy_1yr_mom['SPY'] > 0:
        result['모드'] = '공격자산 (상승장)'
        
        # SPY와 EFA 중 1년 수익률이 높은 자산 선택
        attack_mom = calculate_momentum(data[ASSET_UNIVERSE['공격자산']], 12)
        best_asset = attack_mom.idxmax()
        
        result['추천_포트폴리오'] = {best_asset: '100%'}
        result['상세_수익률'] = attack_mom.to_dict()
        
    # 안전자산 모드: SPY 1년 수익률 <= 0
    else:
        result['모드'] = '안전자산 (하락장)'
        
        # 8개 안전자산의 6개월 수익률 계산
        safe_mom = calculate_momentum(data[ASSET_UNIVERSE['안전자산']], 6)
        
        # 상위 3개 채권 선정
        top_3 = safe_mom.nlargest(3)
        
        portfolio = {}
        cash_ratio = 0
        
        for asset, mom in top_3.items():
            if mom > 0:
                portfolio[asset] = '33.3%'
            else:
                cash_ratio += 33.3
        
        if cash_ratio > 0:
            portfolio['현금(CASH)'] = f"{cash_ratio:.1f}%"
            
        result['추천_포트폴리오'] = portfolio
        result['상세_수익률'] = safe_mom.to_dict()

    return result

# 5. Streamlit UI
st.title('변형 듀얼모멘텀 전략 자동 계산기')
st.markdown("""
이 앱은 강환국님의 **변형 듀얼모멘텀 전략**에 따라 이번 달 마지막 거래일에 매수해야 할 자산을 계산해 줍니다.
- **공격자산**: SPY(미국), EFA(글로벌) (1년 수익률 기준)
- **안전자산**: SHY, IEF, TLT, TIP, LQD, HYG, BNDX, EMB (6개월 수익률 기준)
""")

if st.button('이번 달 매수 자산 계산하기'):
    with st.spinner('데이터를 가져와 계산 중입니다...'):
        result = run_modified_dual_momentum()
        
        if "error" in result:
            st.error(result["error"])
        else:
            st.subheader(f"현재 시장 모드: {result['모드']}")
            
            st.success("이번 달 추천 포트폴리오:")
            for asset, weight in result['추천_포트폴리오'].items():
                st.write(f"- **{asset}**: {weight}")
                
            with st.expander("상세 수익률 데이터 보기"):
                st.write("기준: (현재 월말 종가 / 과거 월말 종가) - 1")
                mom_df = pd.DataFrame(list(result['상세_수익률'].items()), columns=['자산', '수익률'])
                mom_df['수익률'] = mom_df['수익률'].apply(lambda x: f"{x:.2%}")
                st.dataframe(mom_df)

st.caption("주의: 이 코드는 종가(Adj Close) 기반으로 단순 계산된 결과이며, 실제 투자 시에는 배당락, 거래 수수료, 세금 등을 고려해야 합니다.")
